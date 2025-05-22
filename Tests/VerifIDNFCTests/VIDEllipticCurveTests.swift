//
//  VIDEllipticCurveTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//
//  The EC arithmetic is validated against ICAO Doc 9303 Part 11, Appendix G.1
//  (PACE-ECDH-GM, brainpoolP256r1). If any assertion fails, the curve math is
//  wrong. This proves the hardest part of PACE without any hardware.
//

import BigInt
import Foundation
import Testing
@testable import VerifIDNFC

@Suite struct EllipticCurveTests {

    private let curve = VIDStandardCurves.brainpoolP256r1

    private func big(_ hex: String) -> BigUInt { BigUInt(hex.filter(\.isHexDigit), radix: 16)! }

    @Test func generatorIsOnCurve() {
        #expect(curve.isOnCurve(curve.generator))
    }

    @Test func rejectsOffCurvePoint() {
        let bogus = VIDECPoint(x: 1, y: 1)
        #expect(curve.isOnCurve(bogus) == false)
    }

    // Appendix G.1: terminal mapping public key = t·G.
    @Test func scalarMultOfGeneratorMatchesWorkedExample() {
        let t = big("7F4EF07B9EA82FD78AD689B38D0BC78CF21F249D953BC46F4C6E19259C010F99")
        let expected = VIDECPoint(
            x: big("7ACF3EFC982EC45565A4B155129EFBC74650DCBFA6362D896FC70262E0C2CC5E"),
            y: big("544552DCB6725218799115B55C9BAA6D9F6BC3A9618E70C25AF71777A9C4922D")
        )
        #expect(curve.multiply(t, curve.generator) == expected)
    }

    // Appendix G.1: shared secret H = t · chipMappingPublicKey.
    @Test func ecdhSharedSecretMatchesWorkedExample() {
        let t = big("7F4EF07B9EA82FD78AD689B38D0BC78CF21F249D953BC46F4C6E19259C010F99")
        let chipMapPub = VIDECPoint(
            x: big("824FBA91C9CBE26BEF53A0EBE7342A3BF178CEA9F45DE0B70AA601651FBA3F57"),
            y: big("30D8C879AAA9C9F73991E61B58F4D52EB87A0A0C709A49DC63719363CCD13C54")
        )
        let expectedH = VIDECPoint(
            x: big("60332EF2450B5D247EF6D3868397D398852ED6E8CAF6FFEEF6BF85CA57057FD5"),
            y: big("0840CA7415BAF3E43BD414D35AA4608B93A2CAF3A4E3EA4E82C9C13D03EB7181")
        )
        #expect(curve.multiply(t, chipMapPub) == expectedH)
    }

    // Appendix G.1: mapped generator Ĝ = s·G + H (the Generic Mapping formula).
    @Test func genericMappingMatchesWorkedExample() {
        let s = big("3F00C4D39D153F2B2A214A078D899B22")
        let sTimesG = curve.multiply(s, curve.generator)
        let h = VIDECPoint(
            x: big("60332EF2450B5D247EF6D3868397D398852ED6E8CAF6FFEEF6BF85CA57057FD5"),
            y: big("0840CA7415BAF3E43BD414D35AA4608B93A2CAF3A4E3EA4E82C9C13D03EB7181")
        )
        let mappedGenerator = curve.add(sTimesG, h)
        let expected = VIDECPoint(
            x: big("8CED63C91426D4F0EB1435E7CB1D74A46723A0AF21C89634F65A9AE87A9265E2"),
            y: big("8C879506743F8611AC33645C5B985C80B5F09A0B83407C1B6A4D857AE76FE522")
        )
        #expect(mappedGenerator == expected)
    }

    // Appendix G.1: final ECDH shared secret K = x-coordinate of d·chipEphPub.
    @Test func ephemeralSharedSecretXCoordinateMatchesWorkedExample() {
        let d = big("A73FB703AC1436A18E0CFA5ABB3F7BEC7A070E7A6788486BEE230C4A22762595")
        let chipEphPub = VIDECPoint(
            x: big("9E880F842905B8B3181F7AF7CAA9F0EFB743847F44A306D2D28C1D9EC65DF6DB"),
            y: big("7764B22277A2EDDC3C265A9F018F9CB852E111B768B326904B59A0193776F094")
        )
        let shared = curve.multiply(d, chipEphPub)
        let expectedX = big("28768D20701247DAE81804C9E780EDE582A9996DB4A315020B2733197DB84925")
        #expect(shared.x == expectedX)
    }

    @Test func pointEncodingRoundTrips() {
        let encoded = curve.encodePoint(curve.generator)
        #expect(encoded.first == 0x04)
        #expect(encoded.count == 1 + 2 * 32)
        #expect(curve.decodePoint(encoded) == curve.generator)
    }
}
