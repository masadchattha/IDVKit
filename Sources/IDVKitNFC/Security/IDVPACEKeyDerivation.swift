//
//  IDVPACEKeyDerivation.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Crypto
import Foundation
import IDVKitMRZ

/// PACE key derivation (ICAO Doc 9303 Part 11 §9.7). The KDF is simply
/// `H(K ‖ counter)`, truncated to the cipher key length — SHA-1 for AES-128,
/// SHA-256 for AES-192/256.
enum IDVPACEKeyDerivation {
    /// Cipher/keying strength selected by the PACE protocol OID.
    enum Cipher {
        case aes128, aes192, aes256

        var keyLength: Int {
            switch self {
            case .aes128: 16
            case .aes192: 24
            case .aes256: 32
            }
        }
    }

    /// KDF counters (ICAO 9303 Part 11 §9.7.1).
    enum Counter: UInt8 {
        case encryption = 1
        case mac = 2
        case password = 3
    }

    /// `KDF(K, c)` — hash `K ‖ counter(4 bytes BE)` and truncate to the key length.
    static func derive(from key: [UInt8], counter: Counter, cipher: Cipher) -> [UInt8] {
        let input = key + [0x00, 0x00, 0x00, counter.rawValue]
        let digest: [UInt8] = switch cipher {
        case .aes128:
            Array(Insecure.SHA1.hash(data: input))
        case .aes192, .aes256:
            Array(SHA256.hash(data: input))
        }
        return Array(digest.prefix(cipher.keyLength))
    }

    /// Derives the PACE password key `K_π` from the MRZ key.
    /// `f(π) = SHA-1(docNumber+cd ‖ birthDate+cd ‖ expiry+cd)`, then `KDF(f(π), 3)`.
    static func passwordKey(from mrzKey: IDVMRZKey, cipher: Cipher) throws -> [UInt8] {
        let mrzInfo = try mrzKey.seedString()
        let fPi = Array(Insecure.SHA1.hash(data: Array(mrzInfo.utf8)))
        return derive(from: fPi, counter: .password, cipher: cipher)
    }

    /// Session encryption key `KS_Enc = KDF(K, 1)`.
    static func encryptionKey(sharedSecret: [UInt8], cipher: Cipher) -> [UInt8] {
        derive(from: sharedSecret, counter: .encryption, cipher: cipher)
    }

    /// Session MAC key `KS_MAC = KDF(K, 2)`.
    static func macKey(sharedSecret: [UInt8], cipher: Cipher) -> [UInt8] {
        derive(from: sharedSecret, counter: .mac, cipher: cipher)
    }
}
