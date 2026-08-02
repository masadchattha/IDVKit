//
//  IDVBACVectorTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//
//  Every value here is transcribed verbatim from ICAO Doc 9303 Part 11,
//  Appendix D ("Worked Example: Basic Access Control"). If any assertion
//  fails, the crypto is wrong — not the test.
//

import Testing
import IDVKitCore
import IDVKitMRZ
@testable import IDVKitNFC

struct BACVectorTests {
    // MARK: MRZ key seed (D.2)

    @Test func mrzInformationSeedString() throws {
        let key = IDVMRZKey(documentNumber: "L898902C", birthDate: "690806", expiryDate: "940623")
        #expect(try key.seedString() == "L898902C<369080619406236")
    }

    @Test func keySeedFromMRZ() throws {
        let key = IDVMRZKey(documentNumber: "L898902C", birthDate: "690806", expiryDate: "940623")
        let seed = try IDVBACKeyDerivation.keySeed(from: key)
        #expect(Hex.string(seed) == "239AB9CB282DAF66231DC5A4DF6BFBAE")
    }

    // MARK: Key derivation (D.2)

    @Test func derivesKEnc() {
        let seed = Hex.bytes("239AB9CB282DAF66231DC5A4DF6BFBAE")
        let kEnc = IDVBACKeyDerivation.deriveKey(keySeed: seed, type: .encryption)
        #expect(Hex.string(kEnc) == "AB94FDECF2674FDFB9B391F85D7F76F2")
    }

    @Test func derivesKMac() {
        let seed = Hex.bytes("239AB9CB282DAF66231DC5A4DF6BFBAE")
        let kMac = IDVBACKeyDerivation.deriveKey(keySeed: seed, type: .mac)
        #expect(Hex.string(kMac) == "7962D9ECE03D1ACD4C76089DCE131543")
    }

    // MARK: 3DES + retail MAC (D.3)

    @Test func encryptsAuthenticationTokenEIFD() throws {
        let kEnc = Hex.bytes("AB94FDECF2674FDFB9B391F85D7F76F2")
        let s = Hex.bytes("781723860C06C2264608F91988702212" + "0B795240CB7049B01C19B33E32804F0B")
        let eIFD = try IDVDESCrypto.tripleDESEncrypt(data: s, key: kEnc)
        #expect(Hex.string(eIFD) == "72C29C2371CC9BDB65B779B8E8D37B29ECC154AA56A8799FAE2F498F76ED92F2")
    }

    @Test func computesRetailMACOfEIFD() throws {
        let kMac = Hex.bytes("7962D9ECE03D1ACD4C76089DCE131543")
        let eIFD = Hex.bytes("72C29C2371CC9BDB65B779B8E8D37B29ECC154AA56A8799FAE2F498F76ED92F2")
        let mIFD = try IDVRetailMAC.mac(data: IDVPadding.pad(eIFD), key: kMac)
        #expect(Hex.string(mIFD) == "5F1448EEA8AD90A7")
    }

    // MARK: Full BAC handshake against the worked example (D.3)

    @Test func fullBACHandshakeMatchesAppendixD() async throws {
        let key = IDVMRZKey(documentNumber: "L898902C", birthDate: "690806", expiryDate: "940623")

        // Inject the exact terminal randoms from the worked example.
        let rndIFD = Hex.bytes("781723860C06C226")
        let kIFD = Hex.bytes("0B795240CB7049B01C19B33E32804F0B")
        let injectedRandom: (Int) -> [UInt8] = { count in count == 8 ? rndIFD : kIFD }

        // Scripted chip: replies to GET CHALLENGE, then EXTERNAL AUTHENTICATE.
        let session = IDVBACSession(mrzKey: key)
        let transceiver: IDVBACSession.Transceiver = { command in
            if command.ins == 0x84 { // GET CHALLENGE
                return IDVResponseAPDU(data: Hex.bytes("4608F91988702212"), sw1: 0x90, sw2: 0x00)
            }
            // EXTERNAL AUTHENTICATE → E.IC || M.IC from Appendix D.
            #expect(command.ins == 0x82)
            let response = Hex.bytes(
                "46B9342A41396CD7386BF5803104D7CEDC122B9132139BAF2EEDC94EE178534F" + // E.IC
                    "2F2D235D074D7449" // M.IC
            )
            return IDVResponseAPDU(data: response, sw1: 0x90, sw2: 0x00)
        }

        let sm = try await session.establish(transceive: transceiver, randomBytes: injectedRandom)

        #expect(Hex.string(sm.ksEnc) == "979EC13B1CBFE9DCD01AB0FED307EAE5")
        #expect(Hex.string(sm.ksMac) == "F1CB1F1FB5ADF208806B89DC579DC1F8")
        #expect(Hex.string(sm.ssc) == "887022120C06C226")
    }
}
