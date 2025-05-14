//
//  VIDRetailMAC.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import CommonCrypto
import Foundation
import VerifIDCore

/// ISO/IEC 9797-1 MAC algorithm 3 (retail MAC) with DES, as required by eMRTD
/// Secure Messaging (ICAO Doc 9303 Part 11).
///
/// Construction: the 16-byte key splits into K1 (first 8) and K2 (last 8).
/// CBC-DES the padded message with K1; on the final block, decrypt with K2 then
/// re-encrypt with K1. The 8-byte result is the MAC. Callers pad the message
/// with ISO 9797-1 method 2 (``VIDPadding``) before calling.
enum VIDRetailMAC {

    /// Computes the 8-byte retail MAC over already-padded `data`.
    static func mac(data: [UInt8], key: [UInt8]) throws -> [UInt8] {
        guard key.count == 16 else {
            throw VIDError.accessControlFailed(detail: "retail MAC needs a 16-byte key")
        }
        guard data.count % 8 == 0, !data.isEmpty else {
            throw VIDError.accessControlFailed(detail: "retail MAC input must be padded to 8 bytes")
        }
        let k1 = Array(key[0..<8])
        let k2 = Array(key[8..<16])

        // CBC-DES with K1 across every block; keep the last cipher block.
        var mac = [UInt8](repeating: 0, count: 8) // zero IV
        var offset = 0
        while offset < data.count {
            let block = Array(data[offset..<offset + 8])
            let xored = zip(block, mac).map(^)
            mac = try VIDDESCrypto.singleDES(
                operation: CCOperation(kCCEncrypt), data: xored, key: k1, iv: [UInt8](repeating: 0, count: 8)
            )
            offset += 8
        }

        // Final transform: DES-decrypt with K2, then DES-encrypt with K1.
        let decrypted = try VIDDESCrypto.singleDES(
            operation: CCOperation(kCCDecrypt), data: mac, key: k2, iv: [UInt8](repeating: 0, count: 8)
        )
        return try VIDDESCrypto.singleDES(
            operation: CCOperation(kCCEncrypt), data: decrypted, key: k1, iv: [UInt8](repeating: 0, count: 8)
        )
    }
}
