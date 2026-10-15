//
//  IDVPACEHandlerTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//
//  End-to-end PACE handshake replayed against the ICAO Doc 9303 Part 11
//  Appendix G.1 worked example (MRZ password, brainpoolP256r1, AES-128). The
//  scripted chip returns Appendix G's exact responses; with Appendix G's
//  terminal randoms injected, the handler must derive the published session keys.
//

import BigInt
import Foundation
import IDVKitMRZ
@testable import IDVKitNFC
import Testing

struct PACEHandlerTests {
    /// Standard ICAO PACE worked-example MRZ (yields K_π = 89DED1…2849DD).
    private let mrzKey = IDVMRZKey(documentNumber: AppendixG.documentNumber, birthDate: AppendixG.birthDate, expiryDate: AppendixG.expiryDate)

    @Test func fullPACEHandshakeMatchesAppendixG() async throws {
        // Scripted chip: each response carries its data DO plus the 9000 status.
        let ok: [UInt8] = [0x90, 0x00]
        let chip = ScriptedChip(responses: [ok] + AppendixG.generalAuthenticateResponses.map { $0 + ok })

        // Inject Appendix G's terminal mapping key t, then ephemeral key d.
        let scalars = try AppendixG.terminalScalarsHex.map { try #require(BigUInt($0, radix: 16)) }
        let scalarBox = ScalarBox(scalars)

        let info = try IDVPACEInfo.parse(cardAccess: AppendixG.cardAccess)
        let curve = try #require(IDVStandardCurves.curve(parameterId: 13))

        let handler = IDVPACEHandler(mrzKey: mrzKey, info: info, curve: curve)
        let sm = try await handler.run(transceive: chip.transceive) { _ in scalarBox.next() }

        #expect(Hex.string(sm.ksEnc) == AppendixG.ksEncHex)
        #expect(Hex.string(sm.ksMac) == AppendixG.ksMacHex)
        #expect(sm.mode == .aes)
        #expect(sm.ssc.count == 16)
    }
}

/// Returns pre-scripted responses in order, ignoring command contents.
private final class ScriptedChip: @unchecked Sendable {
    private var responses: [[UInt8]]
    private var index = 0
    init(responses: [[UInt8]]) {
        self.responses = responses
    }

    func transceive(_ command: IDVCommandAPDU) async throws -> IDVResponseAPDU {
        defer { index += 1 }
        let bytes = responses[index]
        let data = Array(bytes.dropLast(2))
        return IDVResponseAPDU(data: data, sw1: bytes[bytes.count - 2], sw2: bytes[bytes.count - 1])
    }
}

private final class ScalarBox: @unchecked Sendable {
    private var scalars: [BigUInt]
    private var index = 0
    init(_ scalars: [BigUInt]) {
        self.scalars = scalars
    }

    func next() -> BigUInt {
        defer { index += 1 }; return scalars[index]
    }
}
