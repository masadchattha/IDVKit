//
//  IDVECParameters.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 04/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import BigInt
import Foundation
import IDVKitCore
import SwiftASN1

/// Resolves an elliptic curve from a `SubjectPublicKeyInfo` algorithm parameter,
/// which eMRTD DG14 carries either as a **named-curve OID** or as **explicit
/// domain parameters** (passports commonly use the explicit form).
enum IDVECParameters {
    /// Maps a named-curve OID to a standard curve.
    static func curve(namedCurveOID oid: String) -> IDVEllipticCurve? {
        switch oid {
        case "1.2.840.10045.3.1.7": IDVStandardCurves.nistP256 // secp256r1
        case "1.3.132.0.34": IDVStandardCurves.nistP384 // secp384r1
        case "1.3.132.0.35": IDVStandardCurves.nistP521 // secp521r1
        case "1.3.36.3.3.2.8.1.1.7": IDVStandardCurves.brainpoolP256r1
        case "1.3.36.3.3.2.8.1.1.11": IDVStandardCurves.brainpoolP384r1
        case "1.3.36.3.3.2.8.1.1.13": IDVStandardCurves.brainpoolP512r1
        default: nil
        }
    }

    /// Parses the `parameters` field of an EC `AlgorithmIdentifier` into a curve.
    /// Handles the named-curve OID and the explicit `ECParameters` SEQUENCE.
    static func curve(fromParameters node: ASN1Node) -> IDVEllipticCurve? {
        // Named curve: a bare OID.
        if let oid = try? ASN1ObjectIdentifier(derEncoded: node) {
            return curve(namedCurveOID: oid.description)
        }
        // Explicit ECParameters ::= SEQUENCE { version, fieldID, curve, base,
        //   order, cofactor OPTIONAL }.
        guard case let .constructed(collection) = node.content else { return nil }
        let fields = Array(collection)
        guard fields.count >= 5 else { return nil }

        // fieldID ::= SEQUENCE { fieldType OID, prime INTEGER }
        guard case let .constructed(fieldID) = fields[1].content,
              let prime = integer(Array(fieldID)[1]) else { return nil }

        // curve ::= SEQUENCE { a OCTET STRING, b OCTET STRING, seed BIT STRING? }
        guard case let .constructed(curveSeq) = fields[2].content else { return nil }
        let curveFields = Array(curveSeq)
        guard curveFields.count >= 2,
              let aOctet = try? ASN1OctetString(derEncoded: curveFields[0]),
              let bOctet = try? ASN1OctetString(derEncoded: curveFields[1]) else { return nil }
        let a = BigUInt(Data(aOctet.bytes))
        let b = BigUInt(Data(bOctet.bytes))

        // base ::= OCTET STRING (uncompressed point 04 || Gx || Gy)
        guard let baseOctet = try? ASN1OctetString(derEncoded: fields[3]) else { return nil }
        let base = Array(baseOctet.bytes)
        let byteLength = (prime.bitWidth + 7) / 8
        guard base.first == 0x04, base.count == 1 + 2 * byteLength else { return nil }
        let gx = BigUInt(Data(base[1 ... byteLength]))
        let gy = BigUInt(Data(base[(1 + byteLength)...]))

        // order INTEGER
        guard let order = integer(fields[4]) else { return nil }

        return IDVEllipticCurve(
            p: prime, a: a, b: b,
            generator: IDVECPoint(x: gx, y: gy),
            order: order, fieldByteLength: byteLength
        )
    }

    /// Decodes a DER INTEGER primitive node into a `BigUInt` magnitude.
    private static func integer(_ node: ASN1Node) -> BigUInt? {
        guard case let .primitive(bytes) = node.content else { return nil }
        let magnitude = bytes.first == 0x00 ? bytes.dropFirst() : bytes
        return BigUInt(Data(magnitude))
    }
}
