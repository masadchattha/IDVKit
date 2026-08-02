//
//  IDVPublicKey.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 05/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import _CryptoExtras
import BigInt
import Crypto
import Foundation
import IDVKitCore
import SwiftASN1

/// A document public key (RSA or elliptic-curve) with unified signature
/// verification. EC uses IDVKit's own math, so brainpool curves — which Apple's
/// crypto cannot handle and which most non-US passports use — work here.
enum IDVPublicKey {
    case rsa(_RSA.Signing.PublicKey)
    case ec(curve: IDVEllipticCurve, point: IDVECPoint)

    /// Extracts a public key from a `SubjectPublicKeyInfo` node.
    static func from(spki: ASN1Node) -> IDVPublicKey? {
        guard case let .constructed(outer) = spki.content else { return nil }
        let items = Array(outer)
        guard items.count == 2,
              case let .constructed(alg) = items[0].content,
              let algItems = Optional(Array(alg)), !algItems.isEmpty,
              let oid = try? ASN1ObjectIdentifier(derEncoded: algItems[0]),
              let bits = try? ASN1BitString(derEncoded: items[1]) else { return nil }

        switch oid.description {
        case "1.2.840.113549.1.1.1", "1.2.840.113549.1.1.10": // rsaEncryption / RSASSA-PSS
            guard let rsa = try? DER.parse(Array(bits.bytes)),
                  case let .constructed(parts) = rsa.content else { return nil }
            let kv = Array(parts)
            guard kv.count == 2,
                  case let .primitive(modulus) = kv[0].content,
                  case let .primitive(exponent) = kv[1].content else { return nil }
            let n = modulus.first == 0x00 ? Array(modulus.dropFirst()) : Array(modulus)
            let e = exponent.first == 0x00 ? Array(exponent.dropFirst()) : Array(exponent)
            guard let key = try? _RSA.Signing.PublicKey(n: n, e: e) else { return nil }
            return .rsa(key)

        case "1.2.840.10045.2.1": // id-ecPublicKey
            guard algItems.count >= 2,
                  let curve = IDVECParameters.curve(fromParameters: algItems[1]),
                  let point = curve.decodePoint(Array(bits.bytes)) else { return nil }
            return .ec(curve: curve, point: point)

        default:
            return nil
        }
    }

    /// Verifies `signature` over `message` under this key, using the given
    /// signature-algorithm OID (and, for RSA-PSS, the parsed PSS hash OID).
    func isValidSignature(_ signature: [UInt8], for message: [UInt8], signatureAlgorithmOID: String, pssHashOID: String? = nil) -> Bool {
        switch self {
        case let .rsa(key):
            let isPSS = signatureAlgorithmOID == "1.2.840.113549.1.1.10"
            let padding: _RSA.Signing.Padding = isPSS ? .PSS : .insecurePKCS1v1_5
            let hash = isPSS ? (pssHashOID ?? "1.3.14.3.2.26") : Self.rsaHash(signatureAlgorithmOID)
            let rsaSignature = _RSA.Signing.RSASignature(rawRepresentation: Data(signature))
            switch hash {
            case "2.16.840.1.101.3.4.2.1": return key.isValidSignature(rsaSignature, for: SHA256.hash(data: message), padding: padding)
            case "2.16.840.1.101.3.4.2.2": return key.isValidSignature(rsaSignature, for: SHA384.hash(data: message), padding: padding)
            case "2.16.840.1.101.3.4.2.3": return key.isValidSignature(rsaSignature, for: SHA512.hash(data: message), padding: padding)
            case "1.3.14.3.2.26": return key.isValidSignature(rsaSignature, for: Insecure.SHA1.hash(data: message), padding: padding)
            default: return false
            }

        case let .ec(curve, point):
            guard let hash = IDVSecurityObject.ecdsaHash(signatureOID: signatureAlgorithmOID, digestOID: signatureAlgorithmOID) else { return false }
            return IDVActiveAuthentication.verifyECDSADER(signature: signature, message: message, hash: hash, curve: curve, publicKey: point)
        }
    }

    /// Maps an RSA signature OID to its digest OID.
    private static func rsaHash(_ signatureOID: String) -> String {
        switch signatureOID {
        case "1.2.840.113549.1.1.5": "1.3.14.3.2.26" // SHA-1
        case "1.2.840.113549.1.1.11": "2.16.840.1.101.3.4.2.1" // SHA-256
        case "1.2.840.113549.1.1.12": "2.16.840.1.101.3.4.2.2" // SHA-384
        case "1.2.840.113549.1.1.13": "2.16.840.1.101.3.4.2.3" // SHA-512
        default: "2.16.840.1.101.3.4.2.1" // default SHA-256
        }
    }
}
