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
    private let mrzKey = IDVMRZKey(documentNumber: "T22000129", birthDate: "640812", expiryDate: "101031")

    private func tlv(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        let len: [UInt8] = value.count < 0x80 ? [UInt8(value.count)] : [0x81, UInt8(value.count)]
        return [tag] + len + value
    }

    @Test func fullPACEHandshakeMatchesAppendixG() async throws {
        let z = Hex.bytes("95A3A016522EE98D01E76CB6B98B42C3")
        let chipMapPub = Hex.bytes("04" +
            "824FBA91C9CBE26BEF53A0EBE7342A3BF178CEA9F45DE0B70AA601651FBA3F57" +
            "30D8C879AAA9C9F73991E61B58F4D52EB87A0A0C709A49DC63719363CCD13C54")
        let chipEphPub = Hex.bytes("04" +
            "9E880F842905B8B3181F7AF7CAA9F0EFB743847F44A306D2D28C1D9EC65DF6DB" +
            "7764B22277A2EDDC3C265A9F018F9CB852E111B768B326904B59A0193776F094")
        let tPICC = Hex.bytes("3ABB9674BCE93C08")

        // Scripted chip: each response carries its data DO plus the 9000 status.
        let ok: [UInt8] = [0x90, 0x00]
        let chip = ScriptedChip(responses: [
            ok, // MSE:Set AT
            tlv(0x7C, tlv(0x80, z)) + ok, // GET NONCE
            tlv(0x7C, tlv(0x82, chipMapPub)) + ok, // map nonce
            tlv(0x7C, tlv(0x84, chipEphPub)) + ok, // key agreement
            tlv(0x7C, tlv(0x86, tPICC)) + ok // mutual auth
        ])

        // Inject Appendix G's terminal mapping key t, then ephemeral key d.
        let scalars = try [
            #require(BigUInt(Hex.string(Hex.bytes("7F4EF07B9EA82FD78AD689B38D0BC78CF21F249D953BC46F4C6E19259C010F99")), radix: 16)),
            #require(BigUInt(Hex.string(Hex.bytes("A73FB703AC1436A18E0CFA5ABB3F7BEC7A070E7A6788486BEE230C4A22762595")), radix: 16))
        ]
        let scalarBox = ScalarBox(scalars)

        let info = try IDVPACEInfo.parse(cardAccess: Hex.bytes(
            "31 14 30 12 06 0A 04 00 7F 00 07 02 02 04 02 02 02 01 02 02 01 0D"
        ))
        let curve = try #require(IDVStandardCurves.curve(parameterId: 13))

        let handler = IDVPACEHandler(mrzKey: mrzKey, info: info, curve: curve)
        let sm = try await handler.run(transceive: chip.transceive) { _ in scalarBox.next() }

        #expect(Hex.string(sm.ksEnc) == "F5F0E35C0D7161EE6724EE513A0D9A7F")
        #expect(Hex.string(sm.ksMac) == "FE251C7858B356B24514B3BD5F4297D1")
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
