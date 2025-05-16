//
//  VIDSecureMessagingVectorTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//
//  Values transcribed verbatim from ICAO Doc 9303 Part 11, Appendix D.4
//  ("Secure Messaging" worked example).
//

import Testing
import VerifIDCore
@testable import VerifIDNFC

struct SecureMessagingVectorTests {
    private func session() -> VIDSecureMessaging {
        VIDSecureMessaging(
            ksEnc: Hex.bytes("979EC13B1CBFE9DCD01AB0FED307EAE5"),
            ksMac: Hex.bytes("F1CB1F1FB5ADF208806B89DC579DC1F8"),
            initialSSC: Hex.bytes("887022120C06C226")
        )
    }

    @Test func sscIncrementsAsBigEndianInteger() {
        var sm = session()
        sm.incrementSSC()
        #expect(Hex.string(sm.ssc) == "887022120C06C227")
    }

    // MARK: SELECT EF.COM (D.4)

    @Test func protectsSelectEFCOM() throws {
        var sm = session()
        // Unprotected: 00 A4 02 0C 02 011E
        let command = VIDCommandAPDU(cla: 0x00, ins: 0xA4, p1: 0x02, p2: 0x0C,
                                     data: Hex.bytes("011E"), expectedResponseLength: 0)
        let protected = try sm.protect(command)

        // Expected protected data field from Appendix D.4: DO87 || DO8E.
        let expectedDO87 = "8709016375432908C044F6"
        let expectedDO8E = "8E08BF8B92D635FF24F8"
        #expect(Hex.string(protected.data) == expectedDO87 + expectedDO8E)
        #expect(protected.cla == 0x0C)
        #expect(protected.data.count == 21) // Lc' = 0x15
    }

    @Test func verifiesSelectEFCOMResponse() throws {
        var sm = session()
        // Advance SSC past the command (protect increments once).
        _ = try sm.protect(VIDCommandAPDU(cla: 0x00, ins: 0xA4, p1: 0x02, p2: 0x0C,
                                          data: Hex.bytes("011E"), expectedResponseLength: 0))
        // Response from D.4: DO99(9000) || DO8E.
        let response = VIDResponseAPDU(
            data: Hex.bytes("99029000" + "8E08FA855A5D4C50A8ED"), sw1: 0x90, sw2: 0x00
        )
        let plain = try sm.unprotect(response)
        #expect(plain.isSuccess)
        #expect(plain.data.isEmpty) // SELECT returns no data
    }

    // MARK: READ BINARY first 4 bytes (D.4)

    @Test func protectsAndDecryptsReadBinary() throws {
        var sm = session()
        // Advance SSC to the point before the READ BINARY (two prior commands
        // in the worked example: SELECT command + its response = +2).
        sm.incrementSSC() // simulate SELECT command
        sm.incrementSSC() // simulate SELECT response

        let read = VIDCommandAPDU(cla: 0x00, ins: 0xB0, p1: 0x00, p2: 0x00,
                                  data: [], expectedResponseLength: 4)
        let protected = try sm.protect(read)
        // DO97(04) || DO8E from the worked example.
        #expect(Hex.string(protected.data) == "970104" + "8E08ED6705417E96BA55")

        // Response: DO87(encrypted 60145F01) || DO99 || DO8E.
        let response = VIDResponseAPDU(
            data: Hex.bytes("8709019FF0EC34F9922651" + "99029000" + "8E08AD55CC17140B2DED"),
            sw1: 0x90, sw2: 0x00
        )
        let plain = try sm.unprotect(response)
        #expect(Hex.string(plain.data) == "60145F01")
    }
}
