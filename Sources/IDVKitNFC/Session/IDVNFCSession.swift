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
    import OSLog
    import IDVKitCore

    /// A live CoreNFC ISO 7816 session over a passport chip.
    ///
    /// Wraps `NFCTagReaderSession` + `NFCISO7816Tag` behind an async transceiver so
    /// the BAC and Secure Messaging layers stay transport-agnostic and testable.
    /// iOS auto-SELECTs the eMRTD applet (from the Info.plist `select-identifiers`)
    /// before delivering the tag, so this begins directly at the BAC handshake.
    ///
    /// All CoreNFC types are non-`Sendable` and callbacks arrive on the session's
    /// serial work queue; the tag is confined to this actor for the read's lifetime.
    final class IDVNFCSession: NSObject, @unchecked Sendable {
        private let configuration: IDVNFCConfiguration
        private var session: NFCTagReaderSession?
        private var connectedTag: NFCISO7816Tag?
        private var connectionContinuation: CheckedContinuation<NFCISO7816Tag, Error>?
        private var commandContinuation: CheckedContinuation<IDVResponseAPDU, Error>?
        private var invalidationError: IDVError?
        private var didInvalidate = false

        init(configuration: IDVNFCConfiguration) {
            self.configuration = configuration
        }

        /// `true` when this device can read NFC tags at all.
        static var isReadingAvailable: Bool {
            NFCTagReaderSession.readingAvailable
        }

        /// Opens the session, waits for a connected passport tag, and returns an
        /// async transceiver bound to it plus a handle to drive the alert message.
        func connect() async throws -> NFCISO7816Tag {
            guard Self.isReadingAvailable else { throw IDVError.nfcNotSupported }

            guard let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil) else {
                throw IDVError.nfcNotSupported
            }
            self.session = session
            session.alertMessage = message(for: .holdNearPassport)
            session.begin()
            Logger.nfc.idvDebug("NFC session begun; waiting for a passport tag")

            return try await withCheckedThrowingContinuation { continuation in
                self.connectionContinuation = continuation
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
            return try await withCheckedThrowingContinuation { continuation in
                self.commandContinuation = continuation
                tag.sendCommand(apdu: apdu) { [weak self] data, sw1, sw2, error in
                    guard let self, let pending = commandContinuation else { return }
                    commandContinuation = nil
                    if let error {
                        pending.resume(throwing: Self.mapNFCError(error))
                    } else {
                        pending.resume(returning: IDVResponseAPDU(data: [UInt8](data), sw1: sw1, sw2: sw2))
                    }
                }
            }
        }

        /// Updates the system NFC sheet text (for progress).
        func updateMessage(_ step: IDVNFCConfiguration.ReadStep) {
            session?.alertMessage = message(for: step)
        }

        /// Ends the session with a success or failure indication.
        func finish(success: Bool, errorMessage: String? = nil) {
            didInvalidate = true
            if success {
                session?.alertMessage = message(for: .success)
                session?.invalidate()
            } else {
                session?.invalidate(errorMessage: errorMessage ?? message(for: .failure))
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
            case .success: return "Passport read successfully."
            case .failure: return "Could not read your passport. Please try again."
            }
        }

        // MARK: Error mapping

        static func mapNFCError(_ error: Error) -> IDVError {
            guard let readerError = error as? NFCReaderError else {
                return .nfcSessionFailed(detail: error.localizedDescription)
            }
            switch readerError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                return .cancelledByUser
            case .readerSessionInvalidationErrorSessionTimeout:
                return .nfcSessionFailed(detail: "session timed out")
            case .readerTransceiveErrorTagConnectionLost, .readerTransceiveErrorSessionInvalidated:
                return .nfcTagConnectionLost
            default:
                return .nfcSessionFailed(detail: readerError.localizedDescription)
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
                guard let self else { return }
                if let error {
                    connectedTag = nil
                    connectionContinuation?.resume(throwing: Self.mapNFCError(error))
                } else if let connected = connectedTag {
                    Logger.nfc.idvDebug("Connected to passport chip")
                    connectionContinuation?.resume(returning: connected)
                }
                connectionContinuation = nil
            }
        }

        func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
            didInvalidate = true
            let mapped = Self.mapNFCError(error)
            invalidationError = mapped
            let hadPending = connectionContinuation != nil || commandContinuation != nil
            // Log the exact invalidation reason + whether a read was mid-flight. If a
            // read hangs after Cancel, this reveals whether the session ended while a
            // continuation was pending (should resume instantly) or during off-NFC
            // work (crypto/parse), where the throw only lands at the next command.
            Logger.nfc.idvError("NFC session invalidated: \(error.localizedDescription) → \(mapped.errorDescription ?? "?"); pendingRead=\(hadPending)")
            // Fail whatever is pending so the read returns immediately (e.g. the user
            // cancelled the NFC sheet mid-read).
            connectionContinuation?.resume(throwing: mapped)
            connectionContinuation = nil
            commandContinuation?.resume(throwing: mapped)
            commandContinuation = nil
        }
    }
#endif
