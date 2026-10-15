//
//  IDVDataGroup14.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 04/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore
import OSLog
import SwiftASN1

/// Parsed Chip Authentication material from DG14 (ICAO 9303 Part 11 §6.2 /
/// BSI TR-03110). DG14 (tag `6E`) is a `SET OF SecurityInfo`; the two entries
/// that enable Chip Authentication are `ChipAuthenticationInfo` (the protocol)
/// and `ChipAuthenticationPublicKeyInfo` (the chip's static public key).
struct IDVChipAuthenticationParameters {
    /// The id-CA-* protocol OID (selects cipher/key length).
    let protocolOID: String
    /// The chip's static public key, on `curve`.
    let chipPublicKey: IDVECPoint
    let curve: IDVEllipticCurve
    /// Key identifier when the chip publishes more than one CA key.
    let keyId: Int?

    /// The symmetric cipher the protocol selects (trailing OID arc).
    var cipher: IDVPACEKeyDerivation.Cipher? {
        switch protocolOID.split(separator: ".").last {
        case "2": .aes128
        case "3": .aes192
        case "4": .aes256
        default: nil // 3DES (…3.x.1) — not handled by the AES SM path
        }
    }

    /// Extracts the Active Authentication signature-algorithm OID from DG14's
    /// `ActiveAuthenticationInfo` (id-icao-mrtd-security-aaProtocolObject
    /// 2.23.136.1.1.5), which pins the ECDSA hash. Returns `nil` when absent.
    static func activeAuthenticationSignatureOID(dg14: [UInt8]) -> String? {
        guard let root = try? IDVBERTLV.parse(dg14).tlv, root.tag.first == 0x6E,
              let setNode = try? IDVSecurityObject.parseDERorBER(root.value[...]),
              case let .constructed(entries) = setNode.content else { return nil }
        for entry in entries {
            guard case let .constructed(fields) = entry.content else { continue }
            let items = Array(fields)
            guard let first = items.first, let oid = try? ASN1ObjectIdentifier(derEncoded: first),
                  oid.description == "2.23.136.1.1.5", items.count >= 3,
                  let sigOID = try? ASN1ObjectIdentifier(derEncoded: items[2]) else { continue }
            return sigOID.description
        }
        return nil
    }

    /// Whether DG14 advertises Chip Authentication at all (any `id-CA-*` entry),
    /// regardless of whether IDVKit can perform that algorithm. Lets the caller
    /// tell "chip has no CA" (report *not supported by chip*) apart from "chip has
    /// CA but in an algorithm we don't do yet, e.g. classic DH" (report *not
    /// performed*) — so a genuine chip is never mislabeled as a failure.
    static func advertisesChipAuthentication(dg14: [UInt8]) -> Bool {
        guard let root = try? IDVBERTLV.parse(dg14).tlv, root.tag.first == 0x6E,
              let setNode = try? IDVSecurityObject.parseDERorBER(root.value[...]),
              case let .constructed(entries) = setNode.content else { return false }
        for entry in entries {
            guard case let .constructed(fields) = entry.content,
                  let first = Array(fields).first,
                  let oid = try? ASN1ObjectIdentifier(derEncoded: first) else { continue }
            if oid.description.hasPrefix("0.4.0.127.0.7.2.2.3") {
                return true
            } // id-CA-*
        }
        return false
    }

    /// Parses DG14, returning Chip Authentication parameters if present.
    static func parse(dg14: [UInt8]) -> IDVChipAuthenticationParameters? {
        // DG14 = 6E <len> { SET OF SecurityInfo }.
        guard let root = try? IDVBERTLV.parse(dg14).tlv, root.tag.first == 0x6E,
              let setNode = try? IDVSecurityObject.parseDERorBER(root.value[...]),
              case let .constructed(entries) = setNode.content else { return nil }

        var caProtocolOID: String?
        var caKeyId: Int?
        var pkNode: ASN1Node?
        var pkKeyId: Int?

        for entry in entries {
            guard case let .constructed(fields) = entry.content else { continue }
            let items = Array(fields)
            guard let first = items.first, let oid = try? ASN1ObjectIdentifier(derEncoded: first) else { continue }
            let oidString = oid.description
            Logger.nfc.idvDebug("DG14 SecurityInfo: \(oidString)")

            if oidString.hasPrefix("0.4.0.127.0.7.2.2.3") { // id-CA-*
                caProtocolOID = oidString
                caKeyId = items.count >= 3 ? (try? Int(derEncoded: items[2])) ?? nil : nil
            } else if oidString.hasPrefix("0.4.0.127.0.7.2.2.1") { // id-PK-*
                pkNode = items.count >= 2 ? items[1] : nil // ChipAuthenticationPublicKey (SPKI)
                pkKeyId = items.count >= 3 ? (try? Int(derEncoded: items[2])) ?? nil : nil
            }
        }

        guard let caProtocolOID, let pkNode else {
            Logger.nfc.idvDebug("DG14: no Chip Authentication key pair (CA OID: \(caProtocolOID ?? "none"), PK: \(pkNode == nil ? "none" : "present"))")
            return nil
        }
        // When multiple keys exist, match the CA protocol's keyId to the PK's.
        if let caKeyId, let pkKeyId, caKeyId != pkKeyId {
            return nil
        }

        guard let (curve, point) = parsePublicKey(pkNode) else { return nil }
        return IDVChipAuthenticationParameters(
            protocolOID: caProtocolOID, chipPublicKey: point, curve: curve, keyId: caKeyId ?? pkKeyId
        )
    }

    /// Extracts the curve + EC point from a `SubjectPublicKeyInfo`.
    private static func parsePublicKey(_ spki: ASN1Node) -> (IDVEllipticCurve, IDVECPoint)? {
        // SubjectPublicKeyInfo ::= SEQUENCE { algorithm SEQUENCE { OID, params },
        //   subjectPublicKey BIT STRING }
        guard case let .constructed(outer) = spki.content else { return nil }
        let items = Array(outer)
        guard items.count == 2,
              case let .constructed(algorithm) = items[0].content else { return nil }
        let algFields = Array(algorithm)
        guard algFields.count >= 2, let curve = IDVECParameters.curve(fromParameters: algFields[1]) else {
            return nil
        }
        guard let bitString = try? ASN1BitString(derEncoded: items[1]) else { return nil }
        let point = Array(bitString.bytes)
        guard let decoded = curve.decodePoint(point) else { return nil }
        return (curve, decoded)
    }
}
