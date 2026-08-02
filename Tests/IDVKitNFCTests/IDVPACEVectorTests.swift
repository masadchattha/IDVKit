//
//  IDVPACEVectorTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//
//  Validated against ICAO Doc 9303 Part 11, Appendix G.1 (PACE-ECDH-GM,
//  brainpoolP256r1, AES-128). These prove PACE's key derivation and token
//  construction without any hardware.
//

import Foundation
import Testing
@testable import IDVKitNFC

struct PACEKeyDerivationVectorTests {
    /// K = final ECDH shared-secret x-coordinate from Appendix G.1.
    private let sharedSecret = Hex.bytes("28768D20701247DAE81804C9E780EDE582A9996DB4A315020B2733197DB84925")

    @Test func derivesSessionEncryptionKey() {
        let ksEnc = IDVPACEKeyDerivation.encryptionKey(sharedSecret: sharedSecret, cipher: .aes128)
        #expect(Hex.string(ksEnc) == "F5F0E35C0D7161EE6724EE513A0D9A7F")
    }

    @Test func derivesSessionMACKey() {
        let ksMac = IDVPACEKeyDerivation.macKey(sharedSecret: sharedSecret, cipher: .aes128)
        #expect(Hex.string(ksMac) == "FE251C7858B356B24514B3BD5F4297D1")
    }
}

struct PACETokenVectorTests {
    // id-PACE-ECDH-GM-AES-CBC-CMAC-128 full protocol OID.
    private let protocolOID = Hex.bytes("04007F000702020402 02")
    private let ksMac = Hex.bytes("FE251C7858B356B24514B3BD5F4297D1")

    /// Terminal and chip ephemeral public keys (uncompressed 04‖x‖y).
    private let terminalEphPub = Hex.bytes(
        "04" +
            "2DB7A64C0355044EC9DF190514C625CBA2CEA48754887122F3A5EF0D5EDD301C" +
            "3556F3B3B186DF10B857B58F6A7EB80F20BA5DC7BE1D43D9BF850149FBB36462"
    )
    private let chipEphPub = Hex.bytes(
        "04" +
            "9E880F842905B8B3181F7AF7CAA9F0EFB743847F44A306D2D28C1D9EC65DF6DB" +
            "7764B22277A2EDDC3C265A9F018F9CB852E111B768B326904B59A0193776F094"
    )

    /// T_IFD = CMAC(KS_MAC, 7F49-object-of-CHIP-ephemeral-key).
    @Test func computesTerminalToken() throws {
        let object = IDVPACEToken.publicKeyObject(protocolOID: protocolOID, encodedPoint: chipEphPub)
        let token = try IDVPACEToken.token(peerPublicKeyObject: object, macKey: ksMac)
        #expect(Hex.string(token) == "C2B0BD78D94BA866")
    }

    /// T_PICC = CMAC(KS_MAC, 7F49-object-of-TERMINAL-ephemeral-key).
    @Test func computesChipToken() throws {
        let object = IDVPACEToken.publicKeyObject(protocolOID: protocolOID, encodedPoint: terminalEphPub)
        let token = try IDVPACEToken.token(peerPublicKeyObject: object, macKey: ksMac)
        #expect(Hex.string(token) == "3ABB9674BCE93C08")
    }
}
