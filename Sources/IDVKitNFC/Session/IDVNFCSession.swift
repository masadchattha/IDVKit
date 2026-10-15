//
//  IDVNFCSession.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

#if canImport(CoreNFC)
    import CoreNFC
    import Foundation
    import IDVKitCore
    import OSLog

    /// A live CoreNFC ISO 7816 session over a passport chip.
    ///
    /// Wraps `NFCTagReaderSession` + `NFCISO7816Tag` behind an async transceiver so
    /// the BAC and Secure Messaging layers stay transport-agnostic and testable.
    /// iOS auto-SELECTs the eMRTD applet (from the Info.plist `select-identifiers`)
    /// before delivering the tag.
    ///
    /// All CoreNFC types are non-`Sendable`; callbacks arrive on the session's
    /// private serial queue and the tag is confined to this object for the read.
    final class IDVNFCSession: NSObject, @unchecked Sendable {
        private let configuration: IDVNFCConfiguration
        private var session: NFCTagReaderSession?
        private var connectedTag: NFCISO7816Tag?
        private var connectionContinuation: CheckedContinuation<NFCISO7816Tag, Error>?
        private var connectionGeneration = 0
        private var connectionTimeout: Task<Void, Never>?
        private var commandContinuation: CheckedContinuation<IDVResponseAPDU, Error>?
        private var commandGeneration = 0
        private let continuationLock = OSAllocatedUnfairLock()
        /// Why CoreNFC ended this session, once it has. `nil` while it is alive.
        private(set) var invalidationError: IDVError?
        private var didInvalidate = false
        private var invalidation = IDVInvalidationWaiter()
        private var invalidationWait: Task<Bool, Never>?
        private var finishedAt: Date?
        /// When the last command was sent — logged on invalidation so a device
        /// trace shows whether the session died mid-command or while idle.
        private var lastAPDUAt: Date?
        /// When the transport last failed or a reconnect began. A "cancelled by
        /// user" (code 200) that follows within ``glitchWindow`` is iOS ending the
        /// session after the glitch — nobody taps Cancel 46 ms after a dropped tag.
        private var lastGlitchAt: Date?
        /// Delegate callbacks and command completions land here, never on main, so
        /// app work on the main thread can't delay an APDU and eat session time.
        private let queue = DispatchQueue(label: "dev.idvkit.nfc")

        /// How long one APDU may go unanswered before it fails. A chip that stops
        /// responding mid-handshake would otherwise pin the read until CoreNFC's
        /// ~20 s session limit kills it; failing the single command lets the
        /// handshake/read retry recover in a few seconds instead.
        static let apduTimeout: TimeInterval = 3
        /// Pause before the single retry of a session that iOS refused to start
        /// ("System resource unavailable") — typically the previous session is still
        /// tearing down.
        static let beginRetryDelay: TimeInterval = 1
        /// How long `read()` waits for the invalidation callback after finishing.
        static let invalidationWaitCap: TimeInterval = 2
        /// A code-200 invalidation this soon after a transport glitch is not the user.
        static let glitchWindow: TimeInterval = 1.5

        init(configuration: IDVNFCConfiguration) {
            self.configuration = configuration
        }

        /// `true` when this device can read NFC tags at all.
        static var isReadingAvailable: Bool {
            NFCTagReaderSession.readingAvailable
        }

        /// Takes the process-wide session guard, opens the session and waits for a
        /// connected passport tag. Throws ``IDVError/nfcBusy`` immediately — before
        /// CoreNFC is touched — if another read is still active, and retries a start
        /// that iOS refuses with "System resource unavailable" once.
        /// - Parameter initialStep: the sheet text while polling; a replacement
        ///   session mid-read shows "Keep holding your passport…" instead.
        func connect(initialStep: IDVNFCConfiguration.ReadStep = .holdNearPassport) async throws -> NFCISO7816Tag {
            try IDVNFCSessionGuard.shared.acquire()
            guard Self.isReadingAvailable else {
                IDVNFCSessionGuard.shared.release()
                throw IDVError.nfcNotSupported
            }
            var attempt = 1
            while true {
                do {
                    return try await beginAndAwaitTag(initialStep: initialStep)
                } catch let error as IDVError
                    where Self.shouldRetryBegin(after: error, attempt: attempt, tagConnected: connectedTag != nil) {
                    attempt += 1
                    Logger.nfc.idvDebug("NFC busy at session start; retrying once in \(Int(Self.beginRetryDelay)) s")
                    try? await Task.sleep(for: .seconds(Self.beginRetryDelay))
                    // The refused session has already invalidated and released the
                    // guard; take it again so a read that started meanwhile wins.
                    try IDVNFCSessionGuard.shared.acquire()
                    didInvalidate = false
                    invalidationError = nil
                    invalidation = IDVInvalidationWaiter()
                }
            }
        }

        /// Whether a failed session start deserves the one retry: only a
        /// "System resource unavailable" refusal, before any tag was connected.
        static func shouldRetryBegin(after error: IDVError, attempt: Int, tagConnected: Bool) -> Bool {
            error == .nfcBusy && attempt == 1 && !tagConnected
        }

        private func beginAndAwaitTag(initialStep: IDVNFCConfiguration.ReadStep) async throws -> NFCISO7816Tag {
            guard let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: queue) else {
                IDVNFCSessionGuard.shared.release()
                throw IDVError.nfcNotSupported
            }
            self.session = session
            session.alertMessage = message(for: initialStep)
            session.begin()
            Logger.nfc.idvDebug("NFC session begun; waiting for a passport tag")
            return try await awaitConnection(timeout: nil)
        }

        /// The tag connection is gone but the user is (probably) still holding the
        /// passport: poll again, reconnect, and let the caller redo the handshake and
        /// resume. Bounded by what is left of the read deadline. If CoreNFC ends the
        /// session meanwhile, the thrown error is the mapped invalidation reason and
        /// ``invalidationReason`` is set — the reader then decides on a fresh session.
        func reconnect(deadline: Date) async throws {
            if let invalidationError {
                throw invalidationError
            }
            guard let session, !didInvalidate else { throw IDVError.nfcTagConnectionLost }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0.5 else { throw IDVError.nfcTagConnectionLost }

            lastGlitchAt = Date.now
            connectedTag = nil
            updateMessage(.reconnecting)
            Logger.nfc.idvDebug("Tag connection lost; polling for the passport again (\(Int(remaining)) s left)")
            session.restartPolling()
            _ = try await awaitConnection(timeout: remaining)
            Logger.nfc.idvDebug("Passport reconnected")
        }

        /// Waits for `didDetect` → `connect(to:)`; an optional timeout fails the wait
        /// with `nfcTagConnectionLost`. Generation-guarded like commands, so a late
        /// detection can never resume a later wait.
        private func awaitConnection(timeout: TimeInterval?) async throws -> NFCISO7816Tag {
            let generation: Int = continuationLock.withLock {
                connectionGeneration += 1
                return connectionGeneration
            }
            return try await withCheckedThrowingContinuation { continuation in
                continuationLock.withLock { connectionContinuation = continuation }
                guard let timeout else { return }
                connectionTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled, let pending = self?.takeConnectionContinuation(generation: generation) else { return }
                    Logger.nfc.idvDebug("Passport not found again within the read deadline")
                    pending.resume(throwing: IDVError.nfcTagConnectionLost)
                }
            }
        }

        /// Sends one plain command APDU and returns the response.
        ///
        /// Uses the completion-handler form of `sendCommand` so the pending call can
        /// be failed the instant the session is invalidated (e.g. the user taps
        /// Cancel on the NFC sheet) — the async form abandons its continuation on
        /// invalidation, which would otherwise hang the read forever.
        func transceive(_ command: IDVCommandAPDU) async throws -> IDVResponseAPDU {
            if let invalidationError {
                throw invalidationError
            }
            guard let tag = connectedTag, !didInvalidate else {
                throw IDVError.nfcTagConnectionLost
            }
            guard let apdu = NFCISO7816APDU(data: Data(command.encoded)) else {
                throw IDVError.nfcSessionFailed(detail: "could not encode APDU")
            }
            lastAPDUAt = Date.now
            let generation: Int = continuationLock.withLock {
                commandGeneration += 1
                return commandGeneration
            }
            return try await withCheckedThrowingContinuation { continuation in
                continuationLock.withLock { commandContinuation = continuation }
                // Armed before the send so it cannot miss a fast completion; cancelled
                // by that completion so ~100 sleeping tasks don't pile up per read.
                let timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.apduTimeout))
                    guard !Task.isCancelled, let self, let pending = takeCommandContinuation(generation: generation) else { return }
                    lastGlitchAt = Date.now
                    Logger.nfc.idvDebug("APDU unanswered after \(Int(Self.apduTimeout)) s; failing the command")
                    pending.resume(throwing: IDVError.nfcTagConnectionLost)
                }
                tag.sendCommand(apdu: apdu) { [weak self] data, sw1, sw2, error in
                    guard let self, let pending = takeCommandContinuation(generation: generation) else { return }
                    timeout.cancel()
                    if let error {
                        lastGlitchAt = Date.now
                        pending.resume(throwing: friendly(error))
                    } else {
                        pending.resume(returning: IDVResponseAPDU(data: [UInt8](data), sw1: sw1, sw2: sw2))
                    }
                }
            }
        }

        /// Atomically takes the pending command continuation, but only while it
        /// still belongs to `generation`. The chip callback, the timeout and session
        /// invalidation all race for it; exactly one wins, and a late callback (or a
        /// stale timeout) for an earlier command can never resume a later one.
        private func takeCommandContinuation(generation: Int? = nil) -> CheckedContinuation<IDVResponseAPDU, Error>? {
            continuationLock.withLock {
                if let generation, generation != commandGeneration {
                    return nil
                }
                defer { commandContinuation = nil }
                return commandContinuation
            }
        }

        private func takeConnectionContinuation(generation: Int? = nil) -> CheckedContinuation<NFCISO7816Tag, Error>? {
            continuationLock.withLock {
                if let generation, generation != connectionGeneration {
                    return nil
                }
                defer { connectionContinuation = nil }
                return connectionContinuation
            }
        }

        /// Updates the system NFC sheet text (for progress).
        func updateMessage(_ step: IDVNFCConfiguration.ReadStep) {
            session?.alertMessage = message(for: step)
        }

        /// Ends the session with a success or failure indication. The invalidation
        /// waiter is armed **before** `invalidate()` so the callback can never slip
        /// past it; ``waitForInvalidation()`` then collects the result.
        func finish(success: Bool, errorMessage: String? = nil) {
            didInvalidate = true
            finishedAt = Date.now
            let waiter = invalidation
            invalidationWait = Task { await waiter.wait(cap: Self.invalidationWaitCap) }
            if success {
                session?.alertMessage = message(for: .success)
                session?.invalidate()
            } else {
                session?.invalidate(errorMessage: errorMessage ?? message(for: .failure))
            }
        }

        /// Waits until CoreNFC reports the session invalidated — the sheet is gone
        /// and the next session can start cleanly — capped at
        /// ``invalidationWaitCap``. Returns at once if no session was ever begun.
        func waitForInvalidation() async {
            guard session != nil else { return }
            let signaled: Bool = if let invalidationWait {
                await invalidationWait.value
            } else {
                await invalidation.wait(cap: Self.invalidationWaitCap)
            }
            if !signaled {
                Logger.nfc.idvError("Session did not report invalidation within \(Int(Self.invalidationWaitCap)) s; releasing the session guard anyway")
                IDVNFCSessionGuard.shared.release()
            }
        }

        // MARK: Messages

        private func message(for step: IDVNFCConfiguration.ReadStep) -> String {
            if let custom = configuration.displayMessage?(step) {
                return custom
            }
            switch step {
            case .holdNearPassport: return "Hold your iPhone near your passport."
            case .authenticating: return "Authenticating with your passport…"
            case let .readingDataGroup(name, progress):
                let pct = Int(progress * 100)
                // "verifying" is a phase, not a data group — read it as a verb.
                if name == "verifying" {
                    return "Verifying passport… \(pct)%"
                }
                return "Reading \(name)… \(pct)%"
            case .reconnecting: return "Keep holding your passport…"
            case .success: return "Passport read successfully."
            case .failure: return "Could not read your passport. Please try again."
            }
        }

        // MARK: Error mapping

        /// Maps a CoreNFC error to a friendly ``IDVError``, judging a code 200 by
        /// whether the transport glitched just before it.
        private func friendly(_ error: Error) -> IDVError {
            guard let readerError = error as? NFCReaderError else {
                return .nfcSessionFailed(detail: error.localizedDescription)
            }
            let recentGlitch = lastGlitchAt.map { Date.now.timeIntervalSince($0) < Self.glitchWindow } ?? false
            return Self.friendlyError(code: readerError.code.rawValue, recentGlitch: recentGlitch)
        }

        /// Every CoreNFC code becomes one of IDVKit's own cases — never the raw iOS
        /// text. 200 is "the user cancelled" only when nothing went wrong on the
        /// transport just before; after a glitch it is iOS closing the session.
        static func friendlyError(code: Int, recentGlitch: Bool) -> IDVError {
            switch code {
            case 200: recentGlitch ? .nfcTagConnectionLost : .nfcUserCancelled // UserCanceled
            case 201: .nfcSessionTimeout // SessionTimeout
            case 202: .nfcTagConnectionLost // SessionTerminatedUnexpectedly
            case 203: .nfcBusy // SystemIsBusy — the reader reports it as the budget when it comes late
            case 100 ..< 200: .nfcTagConnectionLost // every transceive failure: connection lost, no response, retries exceeded, …
            default: .nfcSessionFailed(detail: "NFC error \(code)")
            }
        }
    }

    // MARK: - NFCTagReaderSessionDelegate

    extension IDVNFCSession: NFCTagReaderSessionDelegate {
        func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

        func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
            guard let first = tags.first, case let .iso7816(tag) = first else {
                session.restartPolling()
                return
            }
            // Store the (non-Sendable) tag on self up front so the @Sendable
            // completion closure never captures it directly; it only touches self.
            connectedTag = tag
            session.connect(to: first) { [weak self] error in
                guard let self, let pending = takeConnectionContinuation() else { return }
                connectionTimeout?.cancel()
                if let error {
                    connectedTag = nil
                    pending.resume(throwing: friendly(error))
                } else if let connected = connectedTag {
                    Logger.nfc.idvDebug("Connected to passport chip")
                    pending.resume(returning: connected)
                } else {
                    pending.resume(throwing: IDVError.nfcTagConnectionLost)
                }
            }
        }

        func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
            didInvalidate = true
            let mapped = friendly(error)
            invalidationError = mapped
            let pendingConnection = takeConnectionContinuation()
            let pendingCommand = takeCommandContinuation()
            let hadPending = pendingConnection != nil || pendingCommand != nil
            // Log the exact invalidation reason + whether a read was mid-flight. If a
            // read hangs after Cancel, this reveals whether the session ended while a
            // continuation was pending (should resume instantly) or during off-NFC
            // work (crypto/parse), where the throw only lands at the next command.
            let code = (error as? NFCReaderError).map { String($0.code.rawValue) } ?? "n/a"
            let sinceLastAPDU = lastAPDUAt.map { "\(Int(Date.now.timeIntervalSince($0) * 1000)) ms" } ?? "none sent"
            let afterFinish = finishedAt.map { ", \(Int(Date.now.timeIntervalSince($0) * 1000)) ms after finish" } ?? ""
            Logger.nfc.idvError("NFC session invalidated: \(error.localizedDescription) (code \(code)) → \(mapped.errorDescription ?? "?"); pendingRead=\(hadPending); since last APDU: \(sinceLastAPDU)\(afterFinish)")
            // Fail whatever is pending so the read returns immediately (e.g. the user
            // cancelled the NFC sheet mid-read), then free the slot for the next read.
            pendingConnection?.resume(throwing: mapped)
            pendingCommand?.resume(throwing: mapped)
            invalidation.signal()
            IDVNFCSessionGuard.shared.release()
        }
    }
#endif
