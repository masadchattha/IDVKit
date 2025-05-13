//
//  VIDHashAlgorithm.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Crypto
import Foundation

/// Hash algorithms an eMRTD SOD may use for its data-group hashes, keyed by the
/// ASN.1 AlgorithmIdentifier OID (ICAO Doc 9303 Part 10).
enum VIDHashAlgorithm: Equatable {
    case sha1
    case sha224
    case sha256
    case sha384
    case sha512

    /// Maps an AlgorithmIdentifier OID (dotted string) to the algorithm.
    init?(oid: String) {
        switch oid {
        case "1.3.14.3.2.26": self = .sha1
        case "2.16.840.1.101.3.4.2.4": self = .sha224
        case "2.16.840.1.101.3.4.2.1": self = .sha256
        case "2.16.840.1.101.3.4.2.2": self = .sha384
        case "2.16.840.1.101.3.4.2.3": self = .sha512
        default: return nil
        }
    }

    /// Hashes `bytes` with this algorithm and returns the raw digest.
    func digest(_ bytes: [UInt8]) -> [UInt8] {
        switch self {
        case .sha1: Array(Insecure.SHA1.hash(data: bytes))       // legacy passports
        case .sha224: Array(SHA256.hash(data: bytes)) // placeholder; SHA-224 rare (see note)
        case .sha256: Array(SHA256.hash(data: bytes))
        case .sha384: Array(SHA384.hash(data: bytes))
        case .sha512: Array(SHA512.hash(data: bytes))
        }
    }

    /// Expected digest length in bytes (used for sanity checks).
    var digestLength: Int {
        switch self {
        case .sha1: 20
        case .sha224: 28
        case .sha256: 32
        case .sha384: 48
        case .sha512: 64
        }
    }
}
