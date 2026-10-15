//
//  IDVPassportReadOperation.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import BigInt
import CoreGraphics
import Foundation
import IDVKitCore
import IDVKitJPEG2000
import IDVKitMRZ
import ImageIO
import OSLog

/// Drives the passport read once BAC has established a Secure Messaging channel:
/// selects each elementary file and reads it in ≤223-byte chunks (staying well
/// inside CoreNFC's ~20 s per-connection budget), then parses COM/DG1/DG2.
///
/// A `Transceiver` abstracts the wire so the whole read is unit-testable with a
/// scripted chip; the CoreNFC path injects ``IDVNFCSession/transceive(_:)``.
struct IDVPassportReadOperation {
    typealias Transceiver = (IDVCommandAPDU) async throws -> IDVResponseAPDU

    let configuration: IDVNFCConfiguration
    let mrzKey: IDVMRZKey
    /// PACE ephemeral-scalar source; injectable so a scripted chip can replay a
    /// worked example through the whole channel setup.
    var randomScalar: (BigUInt) -> BigUInt = IDVPACEHandler.secureRandomScalar

    /// Reads and parses the passport over an already-open transport.
    /// - Parameters:
    ///   - transceive: sends a plain command APDU, returns the raw response.
    ///   - reconnect: re-finds the tag after the connection dropped; the caller
    ///     then redoes the handshake and resumes. Default: nothing to do.
    ///   - onProgress: called with a data-group label and 0…1 progress.
    /// - Returns: the raw chip data. Pass it to ``finalize(_:)`` **after** the NFC
    ///   session has ended — passive authentication and the DG2 decode are
    ///   CPU-heavy and need no chip, and running them with the field live is what
    ///   let the tag connection drop.
    func run(
        transceive: @escaping Transceiver,
        reconnect: @escaping () async throws -> Void = {},
        onProgress: (String, Double) -> Void = { _, _ in }
    ) async throws -> RawRead {
        let deadline = Date.now.addingTimeInterval(Self.sessionBudget)
        // Every handshake APDU is timed and labelled in the debug log.
        let transceive = Self.timed(transceive)

        // 1. Open the secure channel: PACE when available, else BAC. An unanswered
        // command fails after ~3 s (IDVNFCSession) and the handshake is re-run from
        // the top, so one hang costs seconds, not the whole scan.
        var sm = try await withHandshakeRetry(deadline: deadline, reconnect: reconnect) {
            try await establishSecureChannel(transceive: transceive)
        }
        var caParams: IDVChipAuthenticationParameters?

        // `sm` and `caParams` are captured by reference, so a rebuild below is
        // visible to `secure`.
        let secure: Transceiver = { command in
            let protected = try await sm.protect(command)
            let response = try await transceive(protected)
            return try sm.unprotect(response)
        }

        // Rebuilds the channel after a mid-read glitch: the same sequence as the
        // first handshake (so a PACE read runs PACE again, never BAC), then Chip
        // Authentication again if it had upgraded the channel.
        let reestablish: () async throws -> Void = {
            sm = try await withHandshakeRetry(deadline: deadline, reconnect: reconnect) {
                try await establishSecureChannel(transceive: transceive)
            }
            if let caParams {
                sm = try await IDVChipAuthenticationHandler(parameters: caParams).run(secureTransceive: secure)
            }
        }

        func read(_ fileID: [UInt8], onProgress: (Double) -> Void = { _ in }) async throws -> [UInt8] {
            try await readFile(fileID, using: secure, reestablish: reestablish,
                               deadline: deadline, reconnect: reconnect, onProgress: onProgress)
        }

        // Retain the raw bytes of every data group read; passive authentication
        // hashes them against the SOD.
        var rawGroups: [IDVDataGroupID: [UInt8]] = [:]

        // 2. Read COM to learn which data groups are present.
        onProgress("document", 0.1)
        let comBytes = try await read(IDVDataGroupParser.File.com)
        rawGroups[.com] = comBytes
        let present = (try? IDVDataGroupParser.parseCOMTagList(comBytes)) ?? []
        Logger.nfc.idvDebug("EF.COM read: chip lists \(present.map(\.rawValue).joined(separator: ", "))")

        // 2b. Chip Authentication (anti-clone): read DG14 and, if it advertises
        // Chip Authentication, run it now so it upgrades the secure channel that
        // protects every subsequent read.
        var chipAuthentication: IDVChipAuthenticityResult.CheckStatus = .notSupportedByChip
        if present.contains(.dg14) {
            let dg14 = try await read(IDVDataGroupParser.File.dg14)
            rawGroups[.dg14] = dg14
            if let params = IDVChipAuthenticationParameters.parse(dg14: dg14) {
                do {
                    // A transport glitch during CA is recovered by rebuilding the
                    // channel and re-running CA — only a definitive chip answer may
                    // mark a passport as failed. (`caParams` is still nil here, so
                    // `reestablish` just redoes PACE/BAC.)
                    sm = try await withHandshakeRetry(deadline: deadline, recover: reestablish, reconnect: reconnect) {
                        try await IDVChipAuthenticationHandler(parameters: params).run(secureTransceive: secure)
                    }
                    caParams = params
                    chipAuthentication = .passed
                } catch {
                    chipAuthentication = .failed(reason: "chip authentication failed: \(error.localizedDescription)")
                }
            } else if IDVChipAuthenticationParameters.advertisesChipAuthentication(dg14: dg14) {
                // The chip supports CA in an algorithm IDVKit doesn't do yet (classic
                // DH): a library gap, not a genuineness failure.
                chipAuthentication = .notPerformed(reason: "Chip Authentication uses an algorithm not yet supported by IDVKit (classic DH).")
            }
            Logger.nfc.idvDebug("Chip Authentication: \(chipAuthentication.logLabel)")
        }

        // 3. Read DG1 (MRZ) — always present.
        onProgress("details", 0.3)
        var warnings: [String] = []
        let dg1Bytes = try await read(IDVDataGroupParser.File.dg1)
        rawGroups[.dg1] = dg1Bytes
        let (mrz, checksumFailures) = try IDVDataGroupParser.parseDG1(
            dg1Bytes, strictChecksums: configuration.strictMRZChecksums
        )
        for field in checksumFailures {
            warnings.append("DG1 check digit failed for \(field); accepted because strictMRZChecksums is off (passive authentication still proves integrity).")
        }
        Logger.nfc.idvDebug("DG1 read: \(dg1Bytes.count) bytes\(checksumFailures.isEmpty ? "" : ", \(checksumFailures.count) check-digit warning(s)")")

        // 4. Read DG2 (face) when requested and present — kept raw; `finalize`
        // decodes it after the session so the field is never left idle.
        var groupsRead: [IDVDataGroupID] = [.com, .dg1]
        if configuration.readDataGroups.contains(.dg2), present.contains(.dg2) {
            onProgress("photo", 0.5)
            let dg2Bytes = try await read(IDVDataGroupParser.File.dg2) { fraction in
                onProgress("photo", 0.5 + fraction * 0.4)
            }
            rawGroups[.dg2] = dg2Bytes
            groupsRead.append(.dg2)
            Logger.nfc.idvDebug("DG2 read: \(dg2Bytes.count) bytes (decoded after the session)")
        }

        // 5. Read DG15 (Active Authentication public key) when present.
        var activeAuthKey: IDVActiveAuthentication?
        if present.contains(.dg15) {
            let dg15 = try await read(IDVDataGroupParser.File.dg15)
            rawGroups[.dg15] = dg15
            // DG14's ActiveAuthenticationInfo pins the ECDSA hash, if present.
            let aaSignatureOID = rawGroups[.dg14].flatMap(IDVChipAuthenticationParameters.activeAuthenticationSignatureOID(dg14:))
            activeAuthKey = IDVActiveAuthentication.parse(dg15: dg15, activeAuthSignatureOID: aaSignatureOID)
        }

        // 6. Read EF.SOD for passive authentication.
        onProgress("verifying", 0.95)
        let sodBytes = try await read(IDVDataGroupParser.File.sod)
        Logger.nfc.idvDebug("EF.SOD read: \(sodBytes.count) bytes")

        // 7. Active authentication (standalone challenge/response) — the last APDU.
        var activeAuthentication: IDVChipAuthenticityResult.CheckStatus = .notSupportedByChip
        if let activeAuthKey {
            let outcome: Result<Bool, Error>
            do {
                let verified = try await withHandshakeRetry(deadline: deadline, recover: reestablish, reconnect: reconnect) {
                    try await activeAuthKey.run(secureTransceive: secure)
                }
                outcome = .success(verified)
            } catch {
                outcome = .failure(error)
            }
            activeAuthentication = Self.activeAuthenticationOutcome(outcome)
        }
        Logger.nfc.idvDebug("Active Authentication: \(activeAuthentication.logLabel)")
        onProgress("verifying", 1.0)

        if rawGroups[.dg14] != nil {
            groupsRead.append(.dg14)
        }
        if rawGroups[.dg15] != nil {
            groupsRead.append(.dg15)
        }

        return RawRead(
            mrz: mrz, rawGroups: rawGroups, sodBytes: sodBytes, dataGroupsRead: groupsRead,
            chipAuthentication: chipAuthentication, activeAuthentication: activeAuthentication,
            warnings: warnings
        )
    }

    /// Everything collected from the chip; ``finalize(_:)`` does the rest.
    struct RawRead {
        var mrz: IDVMRZData
        var rawGroups: [IDVDataGroupID: [UInt8]]
        var sodBytes: [UInt8]
        var dataGroupsRead: [IDVDataGroupID]
        var chipAuthentication: IDVChipAuthenticityResult.CheckStatus
        var activeAuthentication: IDVChipAuthenticityResult.CheckStatus
        var warnings: [String]
    }

    /// Passive authentication and the DG2 decode — CPU-heavy, chip-free. Run this
    /// after the NFC session has ended, never with the field live.
    func finalize(_ raw: RawRead) -> IDVPassportData {
        let passive = IDVPassiveAuthenticator(configuration: configuration.passiveAuthentication)
            .verify(sod: raw.sodBytes, dataGroups: raw.rawGroups)
        Logger.nfc.idvDebug("Passive authentication: integrity=\(passive.dataIntegrity.logLabel), trust=\(passive.chainOfTrust.logLabel)")

        var faceImageData: Data?
        var faceImage: CGImage?
        if let dg2 = raw.rawGroups[.dg2] {
            if let face = try? decodeFace(dg2) {
                faceImageData = face.data
                faceImage = face.image
            }
            Logger.nfc.idvDebug("DG2 face \(faceImageData != nil ? "decoded" : "decode failed") (after session)")
        }

        return IDVPassportData(
            mrz: raw.mrz, faceImageData: faceImageData, faceImage: faceImage,
            dataGroupsRead: raw.dataGroupsRead,
            authenticity: IDVChipAuthenticityResult(
                passiveAuthentication: passive,
                chipAuthentication: raw.chipAuthentication,
                activeAuthentication: raw.activeAuthentication
            ),
            warnings: raw.warnings
        )
    }

    /// Only a signature that does not verify is a *failed* Active Authentication.
    /// A dropped connection or a chip error means the check could not be run, and
    /// a genuine passport must never be reported as failing it for that.
    static func activeAuthenticationOutcome(_ outcome: Result<Bool, Error>) -> IDVChipAuthenticityResult.CheckStatus {
        switch outcome {
        case .success(true): .passed
        case .success(false): .failed(reason: "signature did not verify")
        case let .failure(error): .notPerformed(reason: "Active Authentication could not be completed: \(error.localizedDescription)")
        }
    }

    /// A lost tag connection is only worth retrying once the transport has found
    /// the passport again; every other recoverable error just needs the channel
    /// rebuilt. Called before any retry.
    static func recoverTransport(after error: Error, reconnect: () async throws -> Void) async throws {
        if case IDVError.nfcTagConnectionLost = error {
            try await reconnect()
        }
    }

    // MARK: Secure channel

    /// Opens the secure channel per the configured access protocol: PACE when
    /// the chip advertises a supported profile in EF.CardAccess, otherwise BAC.
    ///
    /// Order per ICAO 9303 Part 11: EF.CardAccess (in the master file) → PACE →
    /// SELECT the eMRTD applet under the new secure channel → read files. BAC
    /// talks to the applet directly, so that path selects the applet first.
    func establishSecureChannel(transceive: @escaping Transceiver) async throws -> IDVSecureMessaging {
        switch configuration.accessProtocol {
        case .bacOnly:
            return try await runBAC(transceive: transceive)

        case .paceOnly:
            return try await runPACE(transceive: transceive)

        case .automatic:
            do {
                return try await runPACE(transceive: transceive)
            } catch {
                // A dead transport is not "this chip has no PACE": rethrow so the
                // handshake retry runs PACE again instead of quietly downgrading.
                if let idv = error as? IDVError,
                   [.nfcTagConnectionLost, .nfcUserCancelled, .nfcSessionTimeout, .nfcNotSupported].contains(idv) {
                    throw error
                }
                Logger.nfc.idvDebug("Secure channel: BAC (PACE failed: \(error.localizedDescription))")
                return try await runBAC(transceive: transceive)
            }
        }
    }

    private func runBAC(transceive: @escaping Transceiver) async throws -> IDVSecureMessaging {
        // BAC runs inside the applet. A PACE attempt (or a retry) may have left the
        // master file selected, so select the applet rather than trusting iOS's
        // selection on connect.
        try await selectApplet(using: transceive)
        let bac = try await IDVBACSession(mrzKey: mrzKey).establish(transceive: transceive)
        Logger.nfc.idvDebug("Secure channel: BAC")
        return bac
    }

    private func runPACE(transceive: @escaping Transceiver) async throws -> IDVSecureMessaging {
        // EF.CardAccess lives in the master file, but iOS leaves the eMRTD applet
        // selected on connect — where the same SELECT answers 6A82 and PACE never
        // runs. Select MF first; a chip that refuses is read as before, so chips
        // that already worked keep working.
        if try await transceive(Self.selectMFCommand).isSuccess == false {
            Logger.nfc.idvDebug("SELECT MF refused; reading EF.CardAccess under the applet")
        }
        // 6A82 now means the file really is absent, and BAC is the right protocol.
        let probe = try await transceive(Self.selectEFCommand(IDVDataGroupParser.File.cardAccess))
        if probe.statusWord == 0x6A82 {
            throw IDVError.accessControlFailed(detail: "EF.CardAccess not present; chip does not offer PACE")
        }
        try probe.checkSuccess()

        let cardAccess = try await readSelectedFile(IDVDataGroupParser.File.cardAccess, using: transceive)
        let info = try IDVPACEInfo.parse(cardAccess: cardAccess)
        guard let parameterId = info.parameterId,
              let curve = IDVStandardCurves.curve(parameterId: parameterId) else {
            throw IDVError.accessControlFailed(detail: "unsupported PACE domain parameters")
        }
        var sm = try await IDVPACEHandler(mrzKey: mrzKey, info: info, curve: curve)
            .run(transceive: transceive, randomScalar: randomScalar)
        Logger.nfc.idvDebug("Secure channel: PACE \(info.protocolOID)")

        // Every command after PACE is protected — including the applet SELECT
        // that selecting MF undid.
        let protected = try sm.protect(Self.selectAppletCommand)
        let response = try await transceive(protected)
        try sm.unprotect(response).checkSuccess()
        return sm
    }

    // MARK: Handshake resilience

    /// Total tries for a secure-channel handshake (PACE/BAC or CA): one plus two retries.
    static let handshakeAttempts = 3
    /// The eMRTD application identifier (ICAO 9303 Part 10). iOS selects it on
    /// connect; PACE (which starts in the master file) and BAC select it explicitly.
    static let eMRTDApplicationID: [UInt8] = [0xA0, 0x00, 0x00, 0x02, 0x47, 0x10, 0x01]
    static let selectAppletCommand = IDVCommandAPDU(cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x0C,
                                                    data: eMRTDApplicationID, expectedResponseLength: 0)
    static let selectMFCommand = IDVCommandAPDU(cla: 0x00, ins: 0xA4, p1: 0x00, p2: 0x0C,
                                                data: [0x3F, 0x00], expectedResponseLength: 0)

    /// Runs a handshake, and on a recoverable failure (an unanswered APDU, a lost
    /// tag response, an SM desync) calls `recover` and tries again — up to
    /// ``handshakeAttempts`` times and only while the session deadline allows.
    /// Cancellation, a dead session and an unsupported device are never retried.
    func withHandshakeRetry<T>(
        deadline: Date,
        recover: () async throws -> Void = {},
        reconnect: () async throws -> Void = {},
        _ body: () async throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await body()
            } catch {
                guard attempt < Self.handshakeAttempts, Date.now < deadline, Self.isRecoverable(error) else {
                    throw error
                }
                attempt += 1
                Logger.nfc.idvDebug("Handshake failed (\(error.localizedDescription)); recovering and retrying (attempt \(attempt)/\(Self.handshakeAttempts))")
                try await Self.recoverTransport(after: error, reconnect: reconnect)
                try await recover()
            }
        }
    }

    func selectApplet(using transceive: Transceiver) async throws {
        try await transceive(Self.selectAppletCommand).checkSuccess()
    }

    /// Wraps a transceiver so each handshake APDU logs its step name, round-trip
    /// time and status word when ``IDVLog/isEnabled`` — never any data. READ
    /// BINARY is left out: a DG2 read is ~90 of them and would drown the log.
    static func timed(_ transceive: @escaping Transceiver) -> Transceiver {
        { command in
            guard IDVLog.isEnabled, let step = handshakeStepName(command) else {
                return try await transceive(command)
            }
            let start = Date.now
            do {
                let response = try await transceive(command)
                Logger.nfc.idvDebug("\(step): \(millis(since: start)) ms, SW \(String(format: "%04X", response.statusWord))")
                return response
            } catch {
                Logger.nfc.idvDebug("\(step): \(millis(since: start)) ms, failed — \(error.localizedDescription)")
                throw error
            }
        }
    }

    private static func millis(since start: Date) -> Int {
        Int(Date.now.timeIntervalSince(start) * 1000)
    }

    /// The human name of a handshake APDU, or `nil` for commands not worth logging.
    static func handshakeStepName(_ command: IDVCommandAPDU) -> String? {
        switch (command.ins, command.p1, command.p2) {
        case (0xA4, 0x04, _): "SELECT applet"
        case (0xA4, 0x00, _): "SELECT MF"
        case (0xA4, 0x02, _): "SELECT EF"
        case (0x22, 0xC1, 0xA4): "MSE:Set AT"
        case (0x22, 0x41, 0xA4): "CA MSE"
        case (0x84, _, _): "GET CHALLENGE"
        case (0x82, _, _): "EXTERNAL AUTHENTICATE"
        case (0x88, _, _): "INTERNAL AUTHENTICATE"
        case (0x86, _, _): generalAuthenticateStep(command.data)
        default: nil
        }
    }

    /// Names a General Authenticate by the DO inside its `7C` wrapper: empty →
    /// GET NONCE, `81` map, `83` key agreement, `85` mutual auth, `80` CA.
    private static func generalAuthenticateStep(_ data: [UInt8]) -> String {
        guard data.count >= 2, data[0] == 0x7C else { return "GA" }
        var index = 1
        if data[index] == 0x81 { // long-form length (81 nn)
            index += 1
        }
        index += 1
        guard index < data.count else { return "GA nonce" }
        switch data[index] {
        case 0x81: return "GA map"
        case 0x83: return "GA key"
        case 0x85: return "GA mutual auth"
        case 0x80: return "CA GA"
        default: return "GA"
        }
    }

    // MARK: File reading

    /// How long the whole read gets before retries stop: CoreNFC's ~20 s per tag
    /// connection plus one reconnect with a fresh session.
    static let sessionBudget: TimeInterval = 30
    /// Recoverable read failures tolerated per file before the error surfaces.
    static let maxRetriesPerFile = 3
    /// The READ BINARY length that works on every chip; what a `6C`/`67 00`
    /// correction falls back to.
    static let compatibleChunk = 0xA0
    /// The largest READ BINARY length that still fits a response under SM padding.
    static let maxChunk = 0xDF

    /// The configured READ BINARY chunk size, clamped to `1…maxChunk`.
    private var chunkSize: Int {
        max(1, min(configuration.readChunkSize, Self.maxChunk))
    }

    /// Selects an elementary file and reads it (see ``readSelectedFile``).
    func readFile(
        _ fileID: [UInt8],
        using transceive: Transceiver,
        reestablish: () async throws -> Void = {},
        deadline: Date = .distantFuture,
        reconnect: () async throws -> Void = {},
        onProgress: (Double) -> Void = { _ in }
    ) async throws -> [UInt8] {
        try await select(fileID, using: transceive)
        return try await readSelectedFile(fileID, using: transceive, reestablish: reestablish,
                                          deadline: deadline, reconnect: reconnect, onProgress: onProgress)
    }

    /// Reads the already-selected file `fileID` in chunks: the length header first,
    /// then the rest. A recoverable glitch resumes from the last good offset
    /// (``readChunkResilient``); `fileID` is what the resume re-selects.
    func readSelectedFile(
        _ fileID: [UInt8],
        using transceive: Transceiver,
        reestablish: () async throws -> Void = {},
        deadline: Date = .distantFuture,
        reconnect: () async throws -> Void = {},
        onProgress: (Double) -> Void = { _ in }
    ) async throws -> [UInt8] {
        var retriesLeft = Self.maxRetriesPerFile

        // Read the first 4 bytes to discover the object's total length.
        let head = try await readChunkResilient(fileID: fileID, offset: 0, length: 4,
                                                using: transceive, reestablish: reestablish,
                                                deadline: deadline, reconnect: reconnect, retriesLeft: &retriesLeft)
        let (totalLength, _) = try Self.totalObjectLength(head)

        var data = head
        var offset = head.count
        while offset < totalLength {
            let want = min(chunkSize, totalLength - offset)
            let bytes = try await readChunkResilient(fileID: fileID, offset: offset, length: want,
                                                     using: transceive, reestablish: reestablish,
                                                     deadline: deadline, reconnect: reconnect, retriesLeft: &retriesLeft)
            if bytes.isEmpty {
                break
            }
            data.append(contentsOf: bytes)
            offset += bytes.count
            onProgress(Double(offset) / Double(totalLength))
        }
        return Array(data.prefix(totalLength))
    }

    /// Reads one chunk; on a recoverable failure reconnects if the tag was lost,
    /// re-opens the secure channel, re-selects the file and retries the **same**
    /// offset. `retriesLeft` is shared across a file's chunks.
    func readChunkResilient(
        fileID: [UInt8], offset: Int, length: Int,
        using transceive: Transceiver,
        reestablish: () async throws -> Void,
        deadline: Date,
        reconnect: () async throws -> Void = {},
        retriesLeft: inout Int
    ) async throws -> [UInt8] {
        while true {
            do {
                return try await readBinary(offset: offset, length: length, using: transceive)
            } catch {
                guard retriesLeft > 0, Date.now < deadline, Self.isRecoverable(error) else { throw error }
                retriesLeft -= 1
                Logger.nfc.idvDebug("Read glitch at offset \(offset); recovering and resuming (\(retriesLeft) retries left)")
                // A gone tag must be found again first; retrying blind would burn
                // every retry in milliseconds against a dead connection.
                try await Self.recoverTransport(after: error, reconnect: reconnect)
                try await reestablish()
                try await select(fileID, using: transceive)
            }
        }
    }

    /// SELECT EF (00 A4 02 0C 02 <FID>).
    func select(_ fileID: [UInt8], using transceive: Transceiver) async throws {
        try await transceive(Self.selectEFCommand(fileID)).checkSuccess()
    }

    static func selectEFCommand(_ fileID: [UInt8]) -> IDVCommandAPDU {
        IDVCommandAPDU(cla: 0x00, ins: 0xA4, p1: 0x02, p2: 0x0C, data: fileID, expectedResponseLength: 0)
    }

    /// READ BINARY (00 B0) at a 15-bit offset, honouring the chip's length
    /// corrections: `6C xx` means "ask again with Le = xx", `67 00` means "wrong
    /// length" — in both cases we retry once with the length the chip will accept.
    func readBinary(
        offset: Int, length: Int, using transceive: Transceiver, allowLengthRetry: Bool = true
    ) async throws -> [UInt8] {
        let p1 = UInt8((offset >> 8) & 0x7F)
        let p2 = UInt8(offset & 0xFF)
        let command = IDVCommandAPDU(cla: 0x00, ins: 0xB0, p1: p1, p2: p2,
                                     data: [], expectedResponseLength: length)
        let response = try await transceive(command)
        if response.isSuccess {
            return response.data
        }
        if allowLengthRetry {
            if response.sw1 == 0x6C {
                let correct = response.sw2 == 0 ? Self.compatibleChunk : Int(response.sw2)
                return try await readBinary(offset: offset, length: correct, using: transceive, allowLengthRetry: false)
            }
            if response.sw1 == 0x67, response.sw2 == 0x00 {
                return try await readBinary(offset: offset, length: Self.compatibleChunk, using: transceive, allowLengthRetry: false)
            }
        }
        try response.checkSuccess() // any other status → descriptive throw
        return response.data
    }

    /// Whether a read failure is worth re-opening the channel and resuming. A
    /// non-`IDVError` (an SM parse hiccup) is; an `IDVError` decides for itself.
    static func isRecoverable(_ error: Error) -> Bool {
        (error as? IDVError)?.isRetryableDuringRead ?? true
    }

    /// Parses a BER-TLV object's total on-wire length from its leading bytes.
    static func totalObjectLength(_ head: [UInt8]) throws -> (total: Int, headerBytes: Int) {
        var index = 0
        guard !head.isEmpty else { throw IDVError.dataGroupReadFailed("empty file header") }

        // Tag (1–2 bytes).
        if head[0] & 0x1F == 0x1F {
            index = 2
        } else {
            index = 1
        }
        guard index < head.count else { throw IDVError.dataGroupReadFailed("truncated file header") }

        let lengthByte = head[index]
        index += 1
        var valueLength = 0
        if lengthByte & 0x80 == 0 {
            valueLength = Int(lengthByte)
        } else {
            let count = Int(lengthByte & 0x7F)
            guard count > 0, count <= 3, index + count <= head.count else {
                throw IDVError.dataGroupReadFailed("unsupported file length form")
            }
            for _ in 0 ..< count {
                valueLength = (valueLength << 8) | Int(head[index])
                index += 1
            }
        }
        return (index + valueLength, index)
    }

    // MARK: Face decoding

    /// Decodes the DG2 photo into both the pass-through JPEG `data` (universally
    /// usable; ImageIO cannot read JPEG2000) and the decoded `image`, so callers
    /// who want full fidelity can skip the JPEG re-encode entirely.
    private func decodeFace(_ dg2Bytes: [UInt8]) throws -> (data: Data, image: CGImage?) {
        let (imageBytes, isJPEG2000) = try IDVDataGroupParser.parseDG2FaceImage(dg2Bytes)
        if isJPEG2000 {
            let cgImage = try IDVJPEG2000Decoder.decode(Data(imageBytes))
            return try (Self.jpegData(from: cgImage), cgImage)
        }
        // Already JPEG: pass the original bytes through, and decode a CGImage too.
        return (Data(imageBytes), Self.cgImage(fromJPEG: imageBytes))
    }

    private static func jpegData(from cgImage: CGImage) throws -> Data {
        guard let data = cgImage.idvJPEGData() else {
            throw IDVError.jpeg2000DecodeFailed(detail: "JPEG re-encode failed")
        }
        return data
    }

    private static func cgImage(fromJPEG bytes: [UInt8]) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(Data(bytes) as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
