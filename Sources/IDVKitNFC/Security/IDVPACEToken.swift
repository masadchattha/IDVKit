//
//  IDVPACEToken.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation

/// Builds the PACE mutual-authentication tokens (ICAO Doc 9303 Part 11
/// §4.4.3.4). Each token is an AES-CMAC over the *other* party's ephemeral
/// public key, encoded as a `7F49` public-key object.
enum IDVPACEToken {
    /// Encodes an ephemeral EC public key as the `7F49` object the token MACs:
    /// `7F49 { 06 <protocol OID> 86 <uncompressed EC point> }`.
    static func publicKeyObject(protocolOID: [UInt8], encodedPoint: [UInt8]) -> [UInt8] {
        let oidDO = tlv(0x06, protocolOID)
        let pointDO = tlv(0x86, encodedPoint)
        return tlv(0x7F49, oidDO + pointDO)
    }

    /// Computes an 8-byte token = `CMAC(KS_MAC, 7F49-object-of-peer-public-key)`.
    static func token(
        peerPublicKeyObject: [UInt8], macKey: [UInt8]
    ) throws -> [UInt8] {
        try IDVAESCrypto.cmac(data: peerPublicKeyObject, key: macKey, outputLength: 8)
    }

    // MARK: DER helpers

    private static func tlv(_ tag: UInt16, _ value: [UInt8]) -> [UInt8] {
        let tagBytes: [UInt8] = tag > 0xFF ? [UInt8(tag >> 8), UInt8(tag & 0xFF)] : [UInt8(tag)]
        return tagBytes + length(value.count) + value
    }

    private static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 {
            return [UInt8(n)]
        }
        if n <= 0xFF {
            return [0x81, UInt8(n)]
        }
        return [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
    }
}
