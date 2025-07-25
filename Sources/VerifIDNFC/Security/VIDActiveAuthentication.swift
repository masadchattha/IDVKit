//
//  VIDActiveAuthentication.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 04/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import BigInt
import Foundation
import OSLog
import SwiftASN1
import VerifIDCore

/// Performs Active Authentication (ICAO 9303 Part 11 §6.1): the terminal sends
/// a random challenge; the chip signs it with a private key that never leaves
/// the chip; the terminal verifies against the DG15 public key. Proves the chip
/// is genuine, not a clone.
struct VIDActiveAuthentication {
    typealias Transceiver = (VIDCommandAPDU) async throws -> VIDResponseAPDU

    enum PublicKey {
        case rsa(modulus: BigUInt, exponent: BigUInt)
        case ec(curve: VIDEllipticCurve, point: VIDECPoint)
    }

    let publicKey: PublicKey
    /// The ECDSA hash pinned by DG14's ActiveAuthenticationInfo, when known.
    var ecdsaHash: VIDHashAlgorithm?

    /// Parses DG15 (tag `6F` wrapping a SubjectPublicKeyInfo) into an AA key.
    /// `activeAuthSignatureOID` is the ecdsa-plain OID from DG14, used to pick
    /// the ECDSA hash.
    static func parse(dg15: [UInt8], activeAuthSignatureOID: String? = nil) -> VIDActiveAuthentication? {
        guard var key = parseKey(dg15: dg15) else { return nil }
        key.ecdsaHash = activeAuthSignatureOID.flatMap(hashForECDSA(oid:))
        return key
    }

    private static func parseKey(dg15: [UInt8]) -> VIDActiveAuthentication? {
        guard let root = try? VIDBERTLV.parse(dg15).tlv, root.tag.first == 0x6F,
              let spki = try? VIDSecurityObject.parseDERorBER(root.value[...]),
              case let .constructed(outer) = spki.content else { return nil }
        let items = Array(outer)
        guard items.count == 2, case let .constructed(algorithm) = items[0].content else { return nil }
        let algFields = Array(algorithm)
        guard let algOID = try? ASN1ObjectIdentifier(derEncoded: algFields[0]) else { return nil }

        guard let bitString = try? ASN1BitString(derEncoded: items[1]) else { return nil }
        let keyBytes = Array(bitString.bytes)

        switch algOID.description {
        case "1.2.840.113549.1.1.1": // rsaEncryption
            // RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
            guard let rsa = try? VIDSecurityObject.parseDERorBER(keyBytes[...]),
                  case let .constructed(seq) = rsa.content else { return nil }
            let parts = Array(seq)
            guard parts.count == 2,
                  let n = integer(parts[0]), let e = integer(parts[1]) else { return nil }
            return VIDActiveAuthentication(publicKey: .rsa(modulus: n, exponent: e))

        case "1.2.840.10045.2.1": // id-ecPublicKey
            guard algFields.count >= 2, let curve = VIDECParameters.curve(fromParameters: algFields[1]),
                  let point = curve.decodePoint(keyBytes) else { return nil }
            return VIDActiveAuthentication(publicKey: .ec(curve: curve, point: point))

        default:
            return nil
        }
    }

    /// Runs Active Authentication over the current secure channel.
    func run(secureTransceive: Transceiver, challenge: [UInt8] = VIDActiveAuthentication.randomChallenge()) async throws -> Bool {
        Logger.nfc.vidDebug("AA: INTERNAL AUTHENTICATE")
        // INTERNAL AUTHENTICATE (00 88 00 00 08 <challenge> 00).
        let command = VIDCommandAPDU(cla: 0x00, ins: 0x88, p1: 0x00, p2: 0x00,
                                     data: challenge, expectedResponseLength: 256)
        let response = try await secureTransceive(command)
        try response.checkSuccess()
        Logger.nfc.vidDebug("AA: response \(response.data.count) bytes")
        return verify(signature: response.data, challenge: challenge)
    }

    /// Verifies an Active Authentication signature response.
    func verify(signature: [UInt8], challenge: [UInt8]) -> Bool {
        switch publicKey {
        case let .rsa(n, e):
            guard n > 1, e > 0, !signature.isEmpty else { return false }
            // RSA public op then ISO/IEC 9796-2 message recovery. The block must
            // be the full modulus byte length, left-zero-padded (do not strip).
            let byteLength = (n.bitWidth + 7) / 8
            let representative = BigUInt(Data(signature)).power(e, modulus: n)
            var block = Array(representative.serialize())
            if block.count < byteLength {
                block = Array(repeating: 0, count: byteLength - block.count) + block
            }
            Logger.nfc.vidDebug("AA: RSA \(n.bitWidth)-bit, sig \(signature.count)B, block head 0x\(String(format: "%02X", block.first ?? 0)) tail 0x\(String(format: "%02X", block.last ?? 0))")
            if signature.count != byteLength {
                Logger.nfc.vidError("AA: signature length \(signature.count) != modulus length \(byteLength)")
            }
            return Self.recoverISO9796_2(block: block, challenge: challenge)

        case let .ec(curve, point):
            let hash = ecdsaHash ?? Self.hashForCurve(curve)
            Logger.nfc.vidDebug("AA: ECDSA on \(curve.fieldByteLength * 8)-bit curve, sig \(signature.count)B, hash \(hash)")
            return Self.verifyECDSA(signature: signature, challenge: challenge, curve: curve, publicKey: point, hash: hash)
        }
    }

    /// Maps a TR-03111 ecdsa-plain OID to its hash.
    static func hashForECDSA(oid: String) -> VIDHashAlgorithm? {
        switch oid {
        case "0.4.0.127.0.7.1.1.4.1.1": .sha1
        case "0.4.0.127.0.7.1.1.4.1.3": .sha256
        case "0.4.0.127.0.7.1.1.4.1.4": .sha384
        case "0.4.0.127.0.7.1.1.4.1.5": .sha512
        default: nil // SHA-224 / RIPEMD-160 unsupported by CryptoKit
        }
    }

    // MARK: ISO/IEC 9796-2 Digital Signature Scheme 1 (message recovery)

    /// Recovers and verifies an ISO 9796-2 DS1 block. The signed message is
    /// `M = M1 ‖ M2` where `M2` is the challenge; the block carries `M1` and
    /// `Hash(M1 ‖ M2)`. Handles both the block-filling (`0x6A`) and left-padded
    /// forms.
    static func recoverISO9796_2(block: [UInt8], challenge: [UInt8]) -> Bool {
        var bytes = block
        guard let trailer = bytes.last else { return false }

        let hashAlgorithm: VIDHashAlgorithm
        if trailer == 0xBC {
            bytes.removeLast()
            hashAlgorithm = .sha1
        } else if trailer == 0xCC {
            bytes.removeLast()
            guard let hashID = bytes.popLast() else { return false }
            switch hashID {
            case 0x33: hashAlgorithm = .sha1
            case 0x34: hashAlgorithm = .sha256
            case 0x36: hashAlgorithm = .sha384
            case 0x35: hashAlgorithm = .sha512
            default: return false
            }
        } else {
            return false
        }
        let hashLength = hashAlgorithm.digestLength

        // Header nibble: 0x6 = partial recovery (M2 present, the AA case), 0x4 = total.
        guard let header = bytes.first, (header & 0xC0) == 0x40 else { return false }

        let start: Int
        if header & 0x0F == 0x0A {
            start = 1 // block-filling form: single header byte, M1 follows
        } else if let delimiter = bytes.firstIndex(of: 0xBA) {
            start = delimiter + 1 // padded form: skip up to the 0xBA delimiter
        } else {
            return false
        }

        guard bytes.count >= start + hashLength else { return false }
        let m1 = Array(bytes[start ..< bytes.count - hashLength])
        let recoveredHash = Array(bytes[bytes.count - hashLength ..< bytes.count])
        return hashAlgorithm.digest(m1 + challenge) == recoveredHash
    }

    // MARK: ECDSA

    /// Verifies plain `r‖s` (TR-03111) — the Active Authentication format.
    static func verifyECDSA(signature: [UInt8], challenge: [UInt8], curve: VIDEllipticCurve, publicKey: VIDECPoint, hash: VIDHashAlgorithm) -> Bool {
        let half = signature.count / 2
        guard half > 0, signature.count == half * 2 else { return false }
        let r = BigUInt(Data(signature.prefix(half)))
        let s = BigUInt(Data(signature.suffix(half)))
        return verifyECDSA(r: r, s: s, message: challenge, hash: hash, curve: curve, publicKey: publicKey)
    }

    /// Verifies a DER `ECDSA-Sig-Value SEQUENCE { r, s }` — the CMS/SOD format.
    /// Reused for brainpool DSC keys that swift-certificates cannot handle.
    static func verifyECDSADER(signature: [UInt8], message: [UInt8], hash: VIDHashAlgorithm, curve: VIDEllipticCurve, publicKey: VIDECPoint) -> Bool {
        guard let sequence = try? DER.parse(signature), case let .constructed(parts) = sequence.content else { return false }
        let items = Array(parts)
        guard items.count == 2, let r = integer(items[0]), let s = integer(items[1]) else { return false }
        return verifyECDSA(r: r, s: s, message: message, hash: hash, curve: curve, publicKey: publicKey)
    }

    /// Core ECDSA verification: `(u1·G + u2·Q).x mod n == r`.
    private static func verifyECDSA(r: BigUInt, s: BigUInt, message: [UInt8], hash: VIDHashAlgorithm, curve: VIDEllipticCurve, publicKey: VIDECPoint) -> Bool {
        let n = curve.order
        guard r > 0, r < n, s > 0, s < n else { return false }

        // e = hash(message), truncated to the curve order's bit length.
        let digest = hash.digest(message)
        var e = BigUInt(Data(digest))
        let excess = digest.count * 8 - n.bitWidth
        if excess > 0 {
            e >>= excess
        }

        guard let sInv = s.inverse(n) else { return false }
        let u1 = (e * sInv) % n
        let u2 = (r * sInv) % n
        let point = curve.add(curve.multiply(u1, curve.generator), curve.multiply(u2, publicKey))
        guard !point.isInfinity else { return false }
        return point.x % n == r
    }

    private static func hashForCurve(_ curve: VIDEllipticCurve) -> VIDHashAlgorithm {
        switch curve.fieldByteLength {
        case ...32: .sha256
        case 33 ... 48: .sha384
        default: .sha512
        }
    }

    // MARK: Helpers

    static func randomChallenge() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, 8, &bytes)
        return bytes
    }

    private static func integer(_ node: ASN1Node) -> BigUInt? {
        guard case let .primitive(bytes) = node.content else { return nil }
        let magnitude = bytes.first == 0x00 ? bytes.dropFirst() : bytes
        return BigUInt(Data(magnitude))
    }
}
