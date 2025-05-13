//
//  VIDBACKeyDerivation.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import CommonCrypto
import Foundation
import VerifIDCore
import VerifIDMRZ

/// ICAO Doc 9303 Part 11 key derivation for BAC (3DES).
///
/// `K_seed` comes from the MRZ; encryption and MAC keys are derived from it via
/// the SHA-1-based KDF with a counter. All values are validated against the
/// standard's Appendix D worked example in the test suite.
enum VIDBACKeyDerivation {
    /// KDF counter selecting which key to derive (ICAO 9303 Part 11 §9.7.1.1).
    enum KeyType: UInt8 {
        case encryption = 1
        case mac = 2
    }

    /// Derives the 16-byte `K_seed` from the MRZ key.
    /// SHA-1 of the MRZ-information string, truncated to the first 16 bytes.
    static func keySeed(from mrzKey: VIDMRZKey) throws -> [UInt8] {
        let seedString = try mrzKey.seedString()
        let hash = sha1(Array(seedString.utf8))
        return Array(hash.prefix(16))
    }

    /// Derives a 16-byte 3DES key (K_enc or K_mac) from `keySeed`.
    ///
    /// SHA-1 over `keySeed ‖ counter(4 bytes)`, first 16 bytes taken, then DES
    /// parity bits adjusted on each byte.
    static func deriveKey(keySeed: [UInt8], type: KeyType) -> [UInt8] {
        let counter: [UInt8] = [0x00, 0x00, 0x00, type.rawValue]
        let hash = sha1(keySeed + counter)
        let keyData = Array(hash.prefix(16))
        return adjustParity(keyData)
    }

    /// Sets the low bit of each byte for odd parity, as DES keys require.
    static func adjustParity(_ bytes: [UInt8]) -> [UInt8] {
        bytes.map { byte in
            let ones = byte.nonzeroBitCount - (byte & 1 == 1 ? 1 : 0) // ones in the top 7 bits
            return ones % 2 == 0 ? (byte | 0x01) : (byte & 0xFE)
        }
    }

    static func sha1(_ bytes: [UInt8]) -> [UInt8] {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CC_SHA1(bytes, CC_LONG(bytes.count), &digest)
        return digest
    }
}
