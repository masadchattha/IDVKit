//
//  VIDAESCrypto.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Crypto
import CryptoKit
import Foundation
import VerifIDCore
import _CryptoExtras

/// AES primitives for PACE and its AES Secure Messaging (ICAO 9303 Part 11
/// §9.8.7): AES-CMAC for authentication tokens and DO'8E', AES-CBC (no padding,
/// caller pads with ISO 9797-1 method 2) for message encryption.
enum VIDAESCrypto {

    /// AES-CMAC (SP 800-38B) over `data`, truncated to `outputLength` bytes.
    /// PACE tokens and Secure Messaging both use the 8-byte truncation.
    static func cmac(data: [UInt8], key: [UInt8], outputLength: Int = 8) throws -> [UInt8] {
        var mac = try AES.CMAC(key: SymmetricKey(data: key))
        mac.update(data: data)
        let full = mac.finalize()
        return Array(full.prefix(outputLength))
    }

    /// AES-CBC encrypt with an explicit IV and no padding (data must be a
    /// multiple of the 16-byte block size).
    static func cbcEncrypt(data: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        let sealed = try AES._CBC.encrypt(
            data, using: SymmetricKey(data: key), iv: AES._CBC.IV(ivBytes: iv), noPadding: true
        )
        return Array(sealed)
    }

    /// AES-CBC decrypt with an explicit IV and no padding.
    static func cbcDecrypt(data: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        let plaintext = try AES._CBC.decrypt(
            data, using: SymmetricKey(data: key), iv: AES._CBC.IV(ivBytes: iv), noPadding: true
        )
        return Array(plaintext)
    }

    /// Single-block AES-ECB encryption — used to derive the per-message CBC IV
    /// for AES Secure Messaging (`IV = E(KS_Enc, SSC)`).
    static func encryptBlock(_ block: [UInt8], key: [UInt8]) throws -> [UInt8] {
        // ECB(x) == CBC(x) with a zero IV for a single block.
        try cbcEncrypt(data: block, key: key, iv: [UInt8](repeating: 0, count: 16))
    }
}
