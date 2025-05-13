//
//  VIDDESCrypto.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import CommonCrypto
import Foundation
import VerifIDCore

/// Low-level 3DES primitives used by BAC and Secure Messaging (ICAO Doc 9303
/// Part 11). Two-key 3DES (K1‖K2‖K1) in CBC with a zero IV, per the standard.
///
/// This is DES/3DES only because that is what BAC mandates; PACE (M2 follow-up)
/// uses AES. Implemented over CommonCrypto — no third-party crypto dependency.
enum VIDDESCrypto {

    /// 3DES-CBC encrypt with a zero IV and no padding (data must be a multiple
    /// of 8 bytes — callers pad per ISO 9797-1 method 2 beforehand).
    static func tripleDESEncrypt(data: [UInt8], key: [UInt8]) throws -> [UInt8] {
        try tripleDES(operation: CCOperation(kCCEncrypt), data: data, key: key)
    }

    /// 3DES-CBC decrypt with a zero IV and no padding.
    static func tripleDESDecrypt(data: [UInt8], key: [UInt8]) throws -> [UInt8] {
        try tripleDES(operation: CCOperation(kCCDecrypt), data: data, key: key)
    }

    private static func tripleDES(operation: CCOperation, data: [UInt8], key: [UInt8]) throws -> [UInt8] {
        // Expand a 16-byte 2-key value to the 24-byte K1‖K2‖K1 form 3DES expects.
        let expandedKey: [UInt8]
        switch key.count {
        case kCCKeySize3DES: expandedKey = key
        case 16: expandedKey = key + key[0..<8]
        default: throw VIDError.accessControlFailed(detail: "invalid 3DES key length \(key.count)")
        }

        var output = [UInt8](repeating: 0, count: data.count + kCCBlockSize3DES)
        var movedBytes = 0
        let status = expandedKey.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCCrypt(
                    operation, CCAlgorithm(kCCAlgorithm3DES), CCOptions(0), // no padding, zero IV
                    keyPtr.baseAddress, kCCKeySize3DES, nil,
                    dataPtr.baseAddress, data.count,
                    &output, output.count, &movedBytes
                )
            }
        }
        guard status == kCCSuccess else {
            throw VIDError.accessControlFailed(detail: "3DES operation failed (\(status))")
        }
        return Array(output.prefix(movedBytes))
    }

    /// Single-DES-CBC (zero IV, no padding) — the per-block engine of the
    /// retail MAC. Used internally by ``VIDRetailMAC``.
    static func singleDES(operation: CCOperation, data: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: data.count + kCCBlockSizeDES)
        var movedBytes = 0
        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                data.withUnsafeBytes { dataPtr in
                    CCCrypt(
                        operation, CCAlgorithm(kCCAlgorithmDES), CCOptions(0),
                        keyPtr.baseAddress, kCCKeySizeDES, ivPtr.baseAddress,
                        dataPtr.baseAddress, data.count,
                        &output, output.count, &movedBytes
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw VIDError.accessControlFailed(detail: "DES operation failed (\(status))")
        }
        return Array(output.prefix(movedBytes))
    }
}

/// ISO/IEC 9797-1 padding method 2: append `0x80`, then `0x00` up to a block
/// boundary. Used before both the 3DES cipher and the retail MAC.
enum VIDPadding {
    static func pad(_ data: [UInt8], blockSize: Int = 8) -> [UInt8] {
        var padded = data
        padded.append(0x80)
        while padded.count % blockSize != 0 {
            padded.append(0x00)
        }
        return padded
    }

    /// Removes ISO 9797-1 method 2 padding (strips trailing 0x00 then one 0x80).
    static func unpad(_ data: [UInt8]) -> [UInt8] {
        var end = data.count
        while end > 0, data[end - 1] == 0x00 { end -= 1 }
        if end > 0, data[end - 1] == 0x80 { end -= 1 }
        return Array(data.prefix(end))
    }
}
