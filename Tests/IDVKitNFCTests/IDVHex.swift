//
//  IDVHex.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation

/// Hex helpers for pasting ICAO 9303 worked-example vectors into tests.
enum Hex {
    static func bytes(_ string: String) -> [UInt8] {
        let clean = string.filter(\.isHexDigit)
        var result = [UInt8]()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            result.append(UInt8(clean[index ..< next], radix: 16)!)
            index = next
        }
        return result
    }

    static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// BER-TLV with a 1-, 2- or 3-byte length; `tag` may be multi-byte.
    static func tlv(_ tag: [UInt8], _ value: [UInt8]) -> [UInt8] {
        let n = value.count
        let length: [UInt8] = n < 0x80 ? [UInt8(n)] : n < 0x100 ? [0x81, UInt8(n)] : [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
        return tag + length + value
    }

    static func tlv(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        tlv([tag], value)
    }
}

/// ICAO Doc 9303 Part 11 Appendix G.1 PACE worked example (MRZ password,
/// brainpoolP256r1, AES-128), shared by every test that replays it.
enum AppendixG {
    static let documentNumber = "T22000129", birthDate = "640812", expiryDate = "101031"
    /// EF.CardAccess advertising id-PACE-ECDH-GM-AES-CBC-CMAC-128, parameterId 13.
    static let cardAccess = Hex.bytes("31 14 30 12 06 0A 04 00 7F 00 07 02 02 04 02 02 02 01 02 02 01 0D")
    static let encryptedNonce = Hex.bytes("95A3A016522EE98D01E76CB6B98B42C3")
    static let chipMappingPublicKey = Hex.bytes("04" +
        "824FBA91C9CBE26BEF53A0EBE7342A3BF178CEA9F45DE0B70AA601651FBA3F57" +
        "30D8C879AAA9C9F73991E61B58F4D52EB87A0A0C709A49DC63719363CCD13C54")
    static let chipEphemeralPublicKey = Hex.bytes("04" +
        "9E880F842905B8B3181F7AF7CAA9F0EFB743847F44A306D2D28C1D9EC65DF6DB" +
        "7764B22277A2EDDC3C265A9F018F9CB852E111B768B326904B59A0193776F094")
    static let chipToken = Hex.bytes("3ABB9674BCE93C08")
    /// Terminal mapping key t, then ephemeral key d.
    static let terminalScalarsHex = [
        "7F4EF07B9EA82FD78AD689B38D0BC78CF21F249D953BC46F4C6E19259C010F99",
        "A73FB703AC1436A18E0CFA5ABB3F7BEC7A070E7A6788486BEE230C4A22762595"
    ]
    static let ksEncHex = "F5F0E35C0D7161EE6724EE513A0D9A7F"
    static let ksMacHex = "FE251C7858B356B24514B3BD5F4297D1"
    /// The chip's four General Authenticate replies: nonce, map, key agreement, mutual auth.
    static var generalAuthenticateResponses: [[UInt8]] {
        [
            Hex.tlv(0x7C, Hex.tlv(0x80, encryptedNonce)),
            Hex.tlv(0x7C, Hex.tlv(0x82, chipMappingPublicKey)),
            Hex.tlv(0x7C, Hex.tlv(0x84, chipEphemeralPublicKey)),
            Hex.tlv(0x7C, Hex.tlv(0x86, chipToken))
        ]
    }
}
