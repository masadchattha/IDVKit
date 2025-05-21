//
//  VIDPACEInfoTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation
import Testing
@testable import VerifIDNFC

@Suite struct PACEInfoTests {

    // The PACEInfo from ICAO Doc 9303 Part 11, Appendix G.1, wrapped in an
    // EF.CardAccess SET (31 <len> <PACEInfo>).
    private let cardAccess = Hex.bytes(
        "31 14 30 12 06 0A 04 00 7F 00 07 02 02 04 02 02 02 01 02 02 01 0D"
    )

    @Test func parsesAppendixGPACEInfo() throws {
        let info = try VIDPACEInfo.parse(cardAccess: cardAccess)
        #expect(info.protocolOID == "0.4.0.127.0.7.2.2.4.2.2") // ECDH-GM-AES-CBC-CMAC-128
        #expect(info.version == 2)
        #expect(info.parameterId == 13) // brainpoolP256r1
        #expect(info.mapping == .generic)
        #expect(info.cipher == .aes128)
        #expect(info.isECDH)
    }

    @Test func resolvesCurveFromParameterId() throws {
        let info = try VIDPACEInfo.parse(cardAccess: cardAccess)
        let curve = try #require(info.parameterId.flatMap(VIDStandardCurves.curve(parameterId:)))
        #expect(curve.isOnCurve(curve.generator))
    }

    @Test func classifiesCipherByOIDSuffix() {
        #expect(VIDPACEInfo.cipher(for: "0.4.0.127.0.7.2.2.4.2.2") == .aes128)
        #expect(VIDPACEInfo.cipher(for: "0.4.0.127.0.7.2.2.4.2.4") == .aes256)
    }
}
