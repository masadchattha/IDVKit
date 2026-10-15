//
//  IDVReadOperationTests.swift
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
import IDVKitMRZ
@testable import IDVKitNFC
import Testing

struct ReadOperationTests {
    @Test func parsesTotalObjectLengthShortForm() throws {
        // Tag 60, length 0x14 → total = 2 header + 20 value.
        let (total, header) = try IDVPassportReadOperation.totalObjectLength([0x60, 0x14, 0x5F, 0x01])
        #expect(total == 22)
        #expect(header == 2)
    }

    @Test func parsesTotalObjectLengthLongForm() throws {
        // Tag 75, length 0x82 0x01 0x00 → total = 4 header + 256 value.
        let (total, header) = try IDVPassportReadOperation.totalObjectLength([0x75, 0x82, 0x01, 0x00])
        #expect(total == 260)
        #expect(header == 4)
    }

    @Test func parsesMultiByteTagLength() throws {
        // Multi-byte tag 7F61, short length 0x10.
        let (total, header) = try IDVPassportReadOperation.totalObjectLength([0x7F, 0x61, 0x10, 0x00])
        #expect(total == 3 + 0x10)
        #expect(header == 3)
    }

    // MARK: Resilient read (#0)

    private static let anyKey = IDVMRZKey(documentNumber: "L898902C3", birthDate: "740812", expiryDate: "120415")

    private static func operation(chunkSize: Int) -> IDVPassportReadOperation {
        IDVPassportReadOperation(
            configuration: IDVNFCConfiguration(readChunkSize: chunkSize), mrzKey: anyKey
        )
    }

    /// A fake chip that serves one elementary file over plain APDUs (no Secure
    /// Messaging), optionally failing a READ BINARY at a chosen offset so the
    /// retry-with-resume path can be exercised without BAC/PACE.
    final class ScriptedFile {
        let bytes: [UInt8]
        let failAtOffset: Int
        var failuresLeft: Int
        let error: Error
        private(set) var reads = 0

        init(bytes: [UInt8], failAtOffset: Int = -1, failures: Int = 0,
             error: Error = IDVError.nfcTagConnectionLost) {
            self.bytes = bytes
            self.failAtOffset = failAtOffset
            failuresLeft = failures
            self.error = error
        }

        func transceive(_ command: IDVCommandAPDU) throws -> IDVResponseAPDU {
            switch command.ins {
            case 0xA4: // SELECT
                return IDVResponseAPDU(data: [], sw1: 0x90, sw2: 0x00)
            case 0xB0: // READ BINARY
                let offset = (Int(command.p1 & 0x7F) << 8) | Int(command.p2)
                if offset == failAtOffset, failuresLeft > 0 {
                    failuresLeft -= 1
                    throw error
                }
                reads += 1
                let end = min(offset + command.expectedResponseLength, bytes.count)
                return IDVResponseAPDU(data: Array(bytes[offset ..< end]), sw1: 0x90, sw2: 0x00)
            default:
                return IDVResponseAPDU(data: [], sw1: 0x6A, sw2: 0x82)
            }
        }
    }

    /// Tag 0x60, length 48 → a 50-byte EF whose body counts up 0…47.
    private static func sampleFile() -> [UInt8] {
        [0x60, 48] + (0 ..< 48).map { UInt8($0) }
    }

    @Test func resumesReadFromLastOffsetAfterOneGlitch() async throws {
        let file = Self.sampleFile()
        let chip = ScriptedFile(bytes: file, failAtOffset: 20, failures: 1)
        var reestablishes = 0

        let out = try await Self.operation(chunkSize: 16).readFile(
            [0x01, 0x01],
            using: { try chip.transceive($0) },
            reestablish: { reestablishes += 1 }
        )

        #expect(out == file) // byte-identical after the resume
        #expect(reestablishes == 1) // re-opened the channel exactly once
    }

    @Test func surfacesErrorAfterRetriesExhausted() async {
        let file = Self.sampleFile()
        let chip = ScriptedFile(bytes: file, failAtOffset: 4, failures: .max) // never recovers
        var reestablishes = 0

        await #expect(throws: IDVError.self) {
            _ = try await Self.operation(chunkSize: 4).readFile(
                [0x01, 0x01],
                using: { try chip.transceive($0) },
                reestablish: { reestablishes += 1 }
            )
        }
        #expect(reestablishes == IDVPassportReadOperation.maxRetriesPerFile)
    }

    @Test func readBinaryHonoursSixCLengthCorrection() async throws {
        let payload = (0 ..< 16).map { UInt8($0) }
        var firstCall = true
        let out = try await Self.operation(chunkSize: 0xA0).readBinary(offset: 0, length: 200, using: { command in
            if firstCall {
                firstCall = false
                return IDVResponseAPDU(data: [], sw1: 0x6C, sw2: 0x10) // "ask again with Le = 0x10"
            }
            #expect(command.expectedResponseLength == 0x10)
            return IDVResponseAPDU(data: payload, sw1: 0x90, sw2: 0x00)
        })
        #expect(out == payload)
    }

    @Test func readBinaryFallsBackOnWrongLength() async throws {
        let payload = (0 ..< 16).map { UInt8($0) }
        var firstCall = true
        let out = try await Self.operation(chunkSize: 0xA0).readBinary(offset: 0, length: 200, using: { command in
            if firstCall {
                firstCall = false
                return IDVResponseAPDU(data: [], sw1: 0x67, sw2: 0x00) // wrong length
            }
            #expect(command.expectedResponseLength == 0xA0) // dropped to the compatible size
            return IDVResponseAPDU(data: payload, sw1: 0x90, sw2: 0x00)
        })
        #expect(out == payload)
    }

    // MARK: Handshake resilience (#0b)

    @Test func handshakeRetryRecoversAfterTransientFailure() async throws {
        var calls = 0
        var recoveries = 0
        let value = try await Self.operation(chunkSize: 0xA0).withHandshakeRetry(
            deadline: .distantFuture,
            recover: { recoveries += 1 }
        ) { () throws -> Int in
            calls += 1
            if calls == 1 {
                throw IDVError.nfcTagConnectionLost
            } // e.g. an unanswered MSE:Set AT
            return 42
        }
        #expect(value == 42)
        #expect(calls == 2)
        #expect(recoveries == 1) // re-selected the applet exactly once
    }

    @Test func handshakeRetryStopsAtAttemptCap() async {
        var recoveries = 0
        await #expect(throws: IDVError.self) {
            _ = try await Self.operation(chunkSize: 0xA0).withHandshakeRetry(
                deadline: .distantFuture,
                recover: { recoveries += 1 }
            ) { () throws -> Int in throw IDVError.nfcTagConnectionLost }
        }
        #expect(recoveries == IDVPassportReadOperation.handshakeAttempts - 1)
    }

    @Test func handshakeRetrySkipsTerminalErrorsAndPastDeadline() async {
        var recoveries = 0
        await #expect(throws: IDVError.self) {
            _ = try await Self.operation(chunkSize: 0xA0).withHandshakeRetry(
                deadline: .distantFuture, recover: { recoveries += 1 }
            ) { () throws -> Int in throw IDVError.nfcUserCancelled }
        }
        await #expect(throws: IDVError.self) {
            _ = try await Self.operation(chunkSize: 0xA0).withHandshakeRetry(
                deadline: .distantPast, recover: { recoveries += 1 }
            ) { () throws -> Int in throw IDVError.nfcTagConnectionLost }
        }
        #expect(recoveries == 0)
    }

    @Test func handshakeStepNamesLabelEveryPACEAndCAStep() {
        func apdu(_ cla: UInt8, _ ins: UInt8, _ p1: UInt8, _ p2: UInt8, _ data: [UInt8] = []) -> IDVCommandAPDU {
            IDVCommandAPDU(cla: cla, ins: ins, p1: p1, p2: p2, data: data)
        }
        #expect(IDVPassportReadOperation.handshakeStepName(apdu(0x00, 0xA4, 0x04, 0x0C)) == "SELECT applet")
        #expect(IDVPassportReadOperation.handshakeStepName(apdu(0x00, 0x22, 0xC1, 0xA4)) == "MSE:Set AT")
        #expect(IDVPassportReadOperation.handshakeStepName(apdu(0x10, 0x86, 0, 0, [0x7C, 0x00])) == "GA nonce")
        #expect(IDVPassportReadOperation.handshakeStepName(apdu(0x10, 0x86, 0, 0, [0x7C, 0x03, 0x81, 0x01, 0x04])) == "GA map")
        #expect(IDVPassportReadOperation.handshakeStepName(apdu(0x10, 0x86, 0, 0, [0x7C, 0x81, 0x43, 0x83, 0x41])) == "GA key")
        #expect(IDVPassportReadOperation.handshakeStepName(apdu(0x00, 0x86, 0, 0, [0x7C, 0x0A, 0x85, 0x08])) == "GA mutual auth")
        #expect(IDVPassportReadOperation.handshakeStepName(apdu(0x00, 0x22, 0x41, 0xA4)) == "CA MSE")
        #expect(IDVPassportReadOperation.handshakeStepName(apdu(0x00, 0x86, 0, 0, [0x7C, 0x43, 0x80, 0x41])) == "CA GA")
        #expect(IDVPassportReadOperation.handshakeStepName(apdu(0x00, 0xB0, 0, 0)) == nil) // READ BINARY: not logged
    }

    @Test func transportFailureAfterSessionBudgetBecomesTimeout() {
        let budget = IDVPassportReadOperation.sessionBudget
        #expect(IDVPassportReader.sessionError(for: .nfcTagConnectionLost, elapsed: budget + 1) == .nfcSessionTimeout)
        #expect(IDVPassportReader.sessionError(for: .nfcTagConnectionLost, elapsed: 2) == .nfcTagConnectionLost)
        #expect(IDVPassportReader.sessionError(for: .accessControlFailed(detail: "x"), elapsed: budget + 1) == .accessControlFailed(detail: "x"))
        #expect(IDVPassportReader.sessionError(for: .nfcUserCancelled, elapsed: budget + 1) == .nfcUserCancelled)
    }

    // MARK: Secure-channel sequence (#0c)

    /// ICAO 9303 Part 11 Appendix G.1 worked example: MRZ password,
    /// brainpoolP256r1, AES-128. Replayed through the whole channel setup.
    private static let appendixGKey = IDVMRZKey(documentNumber: AppendixG.documentNumber, birthDate: AppendixG.birthDate, expiryDate: AppendixG.expiryDate)
    private static let appendixGScalars = AppendixG.terminalScalarsHex.compactMap { BigUInt($0, radix: 16) }

    private static func paceOperation(_ accessProtocol: IDVNFCConfiguration.AccessProtocol = .automatic) -> IDVPassportReadOperation {
        var next = 0
        let scalars = appendixGScalars
        return IDVPassportReadOperation(
            configuration: IDVNFCConfiguration(accessProtocol: accessProtocol),
            mrzKey: appendixGKey,
            randomScalar: { _ in
                defer { next += 1 }
                return scalars[next % scalars.count]
            }
        )
    }

    @Test func paceRunsOnceMasterFileIsSelectedFirst() async throws {
        // Real-chip behaviour: EF.CardAccess answers 6A82 while the applet is selected.
        let chip = PACEChip(cardAccessNeedsMF: true)
        let sm = try await Self.paceOperation().establishSecureChannel(transceive: chip.transceive)

        #expect(Hex.string(sm.ksEnc) == AppendixG.ksEncHex) // PACE really ran
        let names = chip.log.map { IDVPassportReadOperation.handshakeStepName($0) ?? "-" }
        #expect(names.prefix(2) == ["SELECT MF", "SELECT EF"]) // MF before CardAccess
        #expect(names.contains("MSE:Set AT"))
        #expect(!chip.log.contains { $0.ins == 0x84 }) // never fell back to BAC
        // ICAO order: the applet is selected last, under secure messaging.
        let last = try #require(chip.log.last)
        #expect(last.cla == 0x0C && last.ins == 0xA4 && last.p1 == 0x04)
    }

    @Test func bacRunsWhenCardAccessIsAbsent() async {
        let chip = PACEChip(cardAccessNeedsMF: true, hasCardAccess: false)
        // BAC itself is scripted to be refused, so the call throws — the assertions
        // are about the sequence that was attempted.
        await #expect(throws: IDVError.self) {
            _ = try await Self.paceOperation().establishSecureChannel(transceive: chip.transceive)
        }
        #expect(!chip.log.contains { $0.ins == 0x22 }) // no PACE attempt
        let names = chip.log.map { IDVPassportReadOperation.handshakeStepName($0) ?? "-" }
        let applet = names.firstIndex(of: "SELECT applet") ?? .max
        let challenge = names.firstIndex(of: "GET CHALLENGE") ?? -1
        #expect(applet < challenge) // applet selected before BAC
    }

    @Test func handshakeRetryRunsPACEAgainRatherThanBAC() async throws {
        let chip = PACEChip(cardAccessNeedsMF: true, dropFirstMSE: true) // one unanswered MSE:Set AT
        let operation = Self.paceOperation()
        let sm = try await operation.withHandshakeRetry(deadline: .distantFuture, recover: {}) {
            try await operation.establishSecureChannel(transceive: chip.transceive)
        }
        #expect(Hex.string(sm.ksEnc) == AppendixG.ksEncHex)
        #expect(chip.log.filter { $0.ins == 0x22 }.count == 2) // PACE attempted twice
        #expect(!chip.log.contains { $0.ins == 0x84 }) // and never BAC
    }

    // MARK: Lost connection, deferred work, AA outcome (#0e)

    @Test func lostConnectionMidFileReconnectsThenResumesFromSavedOffset() async throws {
        let file = Self.sampleFile()
        let chip = ScriptedFile(bytes: file, failAtOffset: 36, failures: 1, error: IDVError.nfcTagConnectionLost)
        var order: [String] = []

        let out = try await Self.operation(chunkSize: 16).readFile(
            [0x01, 0x1D], // EF.SOD
            using: { try chip.transceive($0) },
            reestablish: { order.append("handshake") },
            reconnect: { order.append("reconnect") } // stands in for restartPolling → didDetect → connect
        )

        #expect(out == file) // resumed at offset 36, byte-identical
        #expect(order == ["reconnect", "handshake"]) // find the tag first, then PACE again
    }

    @Test func handshakeRetryReconnectsOnlyForALostTag() async throws {
        var order: [String] = []
        var calls = 0
        _ = try await Self.operation(chunkSize: 0xA0).withHandshakeRetry(
            deadline: .distantFuture,
            recover: { order.append("recover") },
            reconnect: { order.append("reconnect") }
        ) { () throws -> Int in
            calls += 1
            switch calls {
            case 1: throw IDVError.nfcTagConnectionLost
            case 2: throw IDVError.accessControlFailed(detail: "SM desync") // channel rebuild only
            default: return 1
            }
        }
        #expect(order == ["reconnect", "recover", "recover"])
    }

    @Test func activeAuthenticationFailsOnlyOnABadSignature() {
        typealias Status = IDVChipAuthenticityResult.CheckStatus
        #expect(IDVPassportReadOperation.activeAuthenticationOutcome(.success(true)) == .passed)
        #expect(IDVPassportReadOperation.activeAuthenticationOutcome(.success(false)) == Status.failed(reason: "signature did not verify"))
        let lost = IDVPassportReadOperation.activeAuthenticationOutcome(.failure(IDVError.nfcTagConnectionLost))
        guard case .notPerformed = lost else {
            Issue.record("a dropped connection must not count as a failed check: \(lost)")
            return
        }
    }

    @Test func faceIsDecodedInFinalizeAfterTheSession() throws {
        // run() keeps DG2 raw; a chip that goes silent after DG2 can't hurt a decode
        // that only starts once the session is over.
        let jpeg = try #require(Self.tinyJPEG())
        let dg2 = Hex.tlv([0x75], Hex.tlv([0x5F, 0x2E], [UInt8](repeating: 0, count: 46) + jpeg))
        let raw = IDVPassportReadOperation.RawRead(
            mrz: IDVMRZData(format: .td3, documentType: "P", issuingCountry: "UTO", documentNumber: "L898902C3",
                            nationality: "UTO", surname: "ERIKSSON", givenNames: "ANNA MARIA",
                            birthDate: "740812", expiryDate: "120415", sex: "F"),
            rawGroups: [.dg2: dg2], sodBytes: [], dataGroupsRead: [.com, .dg1, .dg2],
            chipAuthentication: .notSupportedByChip, activeAuthentication: .notSupportedByChip, warnings: []
        )

        let passport = Self.operation(chunkSize: 0xA0).finalize(raw)

        #expect(passport.faceImage != nil)
        #expect(Array(passport.faceImageData?.prefix(2) ?? Data()) == [0xFF, 0xD8]) // JPEG SOI
        #expect(passport.dataGroupsRead == [.com, .dg1, .dg2])
    }

    private static func tinyJPEG() -> [UInt8]? {
        guard let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
            let image = context.makeImage(),
            let data = image.idvJPEGData() else { return nil }
        return [UInt8](data)
    }

    // MARK: Fresh session after a dead reconnect (#0f)

    @Test func readResumesByteIdenticalThroughAFreshSession() async throws {
        // The reconnect itself dies (CoreNFC ended the session, code 202); a fresh
        // session takes over, the handshake is redone, and the file resumes at the
        // saved offset — nothing already read is read again.
        let file = Self.sampleFile()
        let chip = ScriptedFile(bytes: file, failAtOffset: 36, failures: 1, error: IDVError.nfcTagConnectionLost)
        var sessions = 1
        var order: [String] = []

        let out = try await Self.operation(chunkSize: 16).readFile(
            [0x01, 0x1D],
            using: { try chip.transceive($0) },
            reestablish: { order.append("handshake") },
            reconnect: {
                // restartPolling → session invalidated unexpectedly → fresh session
                order.append("reconnect-failed-202")
                sessions += 1
                order.append("fresh-session")
            }
        )

        #expect(out == file)
        #expect(sessions == 2)
        #expect(order == ["reconnect-failed-202", "fresh-session", "handshake"])
        #expect(chip.reads == 4) // head + 3 chunks: offset 36 served once, never re-read
    }

    @Test func freshSessionIsEarnedOnlyByASessionCoreNFCEnded() {
        let now = Date.now, later = now.addingTimeInterval(10)
        func decide(_ error: IDVError, ended: Bool = true, used: Bool = false, now: Date = Date.now, deadline: Date = Date.now.addingTimeInterval(10)) -> Bool {
            IDVPassportReader.shouldStartFreshSession(after: error, sessionEnded: ended, alreadyUsed: used, now: now, deadline: deadline)
        }
        #expect(decide(.nfcTagConnectionLost)) // 202, or a 200 right after a glitch
        #expect(decide(.nfcSessionTimeout)) // 201 during the reconnect
        #expect(!decide(.nfcTagConnectionLost, ended: false)) // tag simply not found again: no new session
        #expect(!decide(.nfcUserCancelled)) // a real Cancel is final
        #expect(!decide(.nfcTagConnectionLost, used: true)) // only once per read()
        #expect(!decide(.nfcTagConnectionLost, now: later, deadline: now)) // budget spent
    }

    @Test func isRecoverableExcludesTerminalErrors() {
        #expect(IDVPassportReadOperation.isRecoverable(IDVError.nfcTagConnectionLost))
        #expect(IDVPassportReadOperation.isRecoverable(IDVError.accessControlFailed(detail: "SM desync")))
        #expect(!IDVPassportReadOperation.isRecoverable(IDVError.nfcUserCancelled))
        #expect(!IDVPassportReadOperation.isRecoverable(IDVError.nfcSessionTimeout))
        #expect(!IDVPassportReadOperation.isRecoverable(IDVError.nfcNotSupported))
    }
}

/// A command-aware scripted chip replaying the Appendix G.1 PACE worked example,
/// with the real-chip quirk behind #0c: EF.CardAccess answers `6A82` while the
/// eMRTD applet is selected and only works once the master file is selected.
private final class PACEChip: @unchecked Sendable {
    private(set) var log: [IDVCommandAPDU] = []
    private var mfSelected = false
    private var gaIndex = 0
    private var droppedMSE = false
    private let cardAccessNeedsMF: Bool
    private let hasCardAccess: Bool
    private let dropFirstMSE: Bool

    init(cardAccessNeedsMF: Bool, hasCardAccess: Bool = true, dropFirstMSE: Bool = false) {
        self.cardAccessNeedsMF = cardAccessNeedsMF
        self.hasCardAccess = hasCardAccess
        self.dropFirstMSE = dropFirstMSE
    }

    private static let cardAccess = AppendixG.cardAccess
    private static let ksMac = Hex.bytes(AppendixG.ksMacHex)
    private static let gaResponses = AppendixG.generalAuthenticateResponses

    func transceive(_ command: IDVCommandAPDU) async throws -> IDVResponseAPDU {
        log.append(command)
        func reply(_ data: [UInt8] = [], sw: (UInt8, UInt8) = (0x90, 0x00)) -> IDVResponseAPDU {
            IDVResponseAPDU(data: data, sw1: sw.0, sw2: sw.1)
        }
        switch (command.cla, command.ins, command.p1) {
        case (0x0C, 0xA4, 0x04): // applet SELECT under PACE secure messaging
            return reply(protectedOK())
        case (_, 0xA4, 0x00): // SELECT MF
            mfSelected = true
            return reply()
        case (_, 0xA4, 0x02) where command.data == IDVDataGroupParser.File.cardAccess:
            let present = hasCardAccess && (mfSelected || !cardAccessNeedsMF)
            return present ? reply() : reply(sw: (0x6A, 0x82))
        case (_, 0xA4, _):
            return reply()
        case (_, 0xB0, _): // READ BINARY of EF.CardAccess
            let offset = (Int(command.p1 & 0x7F) << 8) | Int(command.p2)
            let end = min(offset + command.expectedResponseLength, Self.cardAccess.count)
            return reply(Array(Self.cardAccess[offset ..< end]))
        case (_, 0x22, _): // MSE:Set AT
            if dropFirstMSE, !droppedMSE {
                droppedMSE = true
                throw IDVError.nfcTagConnectionLost // what the 3 s APDU timeout surfaces
            }
            return reply()
        case (_, 0x86, _): // General Authenticate
            defer { gaIndex += 1 }
            return reply(Self.gaResponses[gaIndex])
        case (_, 0x84, _): // GET CHALLENGE: refuse, so a BAC fallback fails visibly
            return reply(sw: (0x69, 0x82))
        default:
            return reply()
        }
    }

    /// A secure-messaging "9000" the terminal accepts: DO99 plus AES-CMAC over
    /// SSC‖DO99. Chip-side SSC is 2 for the first reply (1 command, 2 response).
    private func protectedOK() -> [UInt8] {
        let do99: [UInt8] = [0x99, 0x02, 0x90, 0x00]
        let ssc = [UInt8](repeating: 0, count: 15) + [0x02]
        let mac = (try? IDVAESCrypto.cmac(data: IDVPadding.pad(ssc + do99, blockSize: 16), key: Self.ksMac)) ?? []
        return do99 + [0x8E, 0x08] + mac
    }
}
