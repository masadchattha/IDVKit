//
//  IDVX509Certificate.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 05/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import SwiftASN1
import IDVKitCore

/// A minimal X.509 certificate parser (RFC 5280) that extracts only what
/// passport chain-of-trust needs. IDVKit parses certificates itself because
/// swift-certificates rejects brainpool-curve keys, which most non-US Document
/// Signer and CSCA certificates use.
struct IDVX509Certificate {
    /// The exact DER of `tbsCertificate` — the bytes the issuer signed.
    let tbsCertificateDER: [UInt8]
    /// Raw DER of the issuer and subject `Name`s, for byte-exact matching.
    let issuerDER: [UInt8]
    let subjectDER: [UInt8]
    let notBefore: Date?
    let notAfter: Date?
    let publicKey: IDVPublicKey?
    /// Outer signatureAlgorithm OID and the signature bits.
    let signatureAlgorithmOID: String
    /// Inner `tbsCertificate.signature` OID — must equal the outer OID (RFC 5280
    /// §4.1.1.2), else the certificate has been algorithm-substituted.
    let innerSignatureAlgorithmOID: String?
    let signatureValue: [UInt8]
    let subjectKeyIdentifier: [UInt8]?
    let authorityKeyIdentifier: [UInt8]?

    /// Whether the inner and outer signature-algorithm identifiers agree.
    var algorithmConsistent: Bool {
        guard let innerSignatureAlgorithmOID else { return true } // absent → don't penalize
        return innerSignatureAlgorithmOID == signatureAlgorithmOID
    }

    /// A short human description of this certificate's issuer (the CSCA that
    /// signed it) — e.g. `CN=CSCAPKI_PK, C=PK`. Used to tell integrators exactly
    /// which trust anchor is missing.
    var issuerDescription: String {
        Self.describeName(issuerDER)
    }

    /// The issuer's ISO country code (the `C=` attribute), when present.
    var issuerCountry: String? {
        Self.attribute(from: issuerDER, oid: [0x55, 0x04, 0x06])
    }

    /// The Authority Key Identifier (the issuing CSCA's key ID) as uppercase hex.
    var authorityKeyIdentifierHex: String? {
        authorityKeyIdentifier?.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: Parse

    init?(der: [UInt8]) {
        guard let cert = try? IDVSecurityObject.parseDERorBER(der[...]),
              case let .constructed(certParts) = cert.content else { return nil }
        let top = Array(certParts)
        // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
        guard top.count == 3,
              case let .constructed(tbsParts) = top[0].content else { return nil }
        tbsCertificateDER = Array(top[0].encodedBytes)

        // Outer signatureAlgorithm + signatureValue.
        guard case let .constructed(sigAlg) = top[1].content,
              let sigAlgOIDNode = Array(sigAlg).first,
              let sigAlgOID = try? ASN1ObjectIdentifier(derEncoded: sigAlgOIDNode),
              let sigBits = try? ASN1BitString(derEncoded: top[2]) else { return nil }
        signatureAlgorithmOID = sigAlgOID.description
        signatureValue = Array(sigBits.bytes)

        // TBSCertificate ::= SEQUENCE { [0] version?, serialNumber, signature,
        //   issuer, validity, subject, spki, ..., extensions [3]? }
        let tbs = Array(tbsParts)
        let hasVersion = tbs.first.map {
            $0.identifier == ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific)
        } ?? false
        let base = hasVersion ? 1 : 0
        // base+0 serialNumber, +1 signature, +2 issuer, +3 validity, +4 subject, +5 spki
        guard tbs.count >= base + 6 else { return nil }
        // Inner tbsCertificate.signature AlgorithmIdentifier (for the RFC 5280
        // inner/outer consistency check).
        if case let .constructed(innerAlg) = tbs[base + 1].content,
           let innerOIDNode = Array(innerAlg).first,
           let innerOID = try? ASN1ObjectIdentifier(derEncoded: innerOIDNode) {
            innerSignatureAlgorithmOID = innerOID.description
        } else {
            innerSignatureAlgorithmOID = nil
        }
        issuerDER = Array(tbs[base + 2].encodedBytes)
        subjectDER = Array(tbs[base + 4].encodedBytes)
        publicKey = IDVPublicKey.from(spki: tbs[base + 5])

        let validity = Array((try? IDVX509Certificate.children(tbs[base + 3])) ?? [])
        notBefore = validity.count > 0 ? IDVX509Certificate.parseTime(validity[0]) : nil
        notAfter = validity.count > 1 ? IDVX509Certificate.parseTime(validity[1]) : nil

        // Extensions [3] EXPLICIT → SEQUENCE OF Extension.
        var ski: [UInt8]?
        var aki: [UInt8]?
        if tbs.count > base + 6,
           tbs[base + 6].identifier == ASN1Identifier(tagWithNumber: 3, tagClass: .contextSpecific),
           case let .constructed(extWrapper) = tbs[base + 6].content,
           let extSeq = Array(extWrapper).first,
           case let .constructed(exts) = extSeq.content {
            for ext in Array(exts) {
                guard case let .constructed(fields) = ext.content else { continue }
                let items = Array(fields)
                guard let oidNode = items.first,
                      let oid = try? ASN1ObjectIdentifier(derEncoded: oidNode),
                      let valueNode = items.last,
                      case let .primitive(extnValue) = valueNode.content else { continue }
                switch oid.description {
                case "2.5.29.14": ski = IDVX509Certificate.parseSKI(Array(extnValue)) // SubjectKeyIdentifier
                case "2.5.29.35": aki = IDVX509Certificate.parseAKI(Array(extnValue)) // AuthorityKeyIdentifier
                default: break
                }
            }
        }
        subjectKeyIdentifier = ski
        authorityKeyIdentifier = aki
    }

    // MARK: Verification

    /// Verifies that `child` was signed by this certificate (this = issuer/CSCA).
    /// Rejects a child whose inner and outer signature algorithms disagree
    /// (RFC 5280 §4.1.1.2 — algorithm-substitution defense).
    func hasSigned(_ child: IDVX509Certificate) -> Bool {
        guard let publicKey, child.algorithmConsistent else { return false }
        return publicKey.isValidSignature(
            child.signatureValue, for: child.tbsCertificateDER,
            signatureAlgorithmOID: child.signatureAlgorithmOID
        )
    }

    /// Whether this certificate could be `child`'s issuer, by SKI/AKI or by name.
    func isIssuer(of child: IDVX509Certificate) -> Bool {
        if let aki = child.authorityKeyIdentifier, let ski = subjectKeyIdentifier {
            return aki == ski
        }
        return subjectDER == child.issuerDER
    }

    // MARK: Helpers

    /// Builds a short `CN=…, C=…` description from a `Name` DER, for surfacing
    /// which CSCA a document chains to. Falls back to whatever attributes exist.
    static func describeName(_ nameDER: [UInt8]) -> String {
        var parts: [String] = []
        if let cn = attribute(from: nameDER, oid: [0x55, 0x04, 0x03]) {
            parts.append("CN=\(cn)")
        } // commonName
        if let o = attribute(from: nameDER, oid: [0x55, 0x04, 0x0A]) {
            parts.append("O=\(o)")
        } // organizationName
        if let c = attribute(from: nameDER, oid: [0x55, 0x04, 0x06]) {
            parts.append("C=\(c)")
        } // countryName
        return parts.isEmpty ? "unknown issuer" : parts.joined(separator: ", ")
    }

    /// Finds an attribute's string value inside a `Name` DER by its OID body
    /// bytes (e.g. `55 04 03` for commonName). Locates `06 03 <oid>` then reads
    /// the following string TLV — enough for the printable DN attributes CSCAs use.
    static func attribute(from nameDER: [UInt8], oid: [UInt8]) -> String? {
        let needle = [0x06, UInt8(oid.count)] + oid
        guard let start = firstRange(of: needle, in: nameDER) else { return nil }
        var i = start + needle.count
        guard i < nameDER.count else { return nil }
        i += 1 // skip the value's tag (PrintableString/UTF8String/etc.)
        guard i < nameDER.count else { return nil }
        let length = Int(nameDER[i]); i += 1
        guard length < 0x80, i + length <= nameDER.count else { return nil }
        return String(decoding: nameDER[i ..< i + length], as: UTF8.self)
    }

    private static func firstRange(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for i in 0 ... (haystack.count - needle.count) where Array(haystack[i ..< i + needle.count]) == needle {
            return i
        }
        return nil
    }

    private static func children(_ node: ASN1Node) throws -> [ASN1Node] {
        guard case let .constructed(collection) = node.content else { return [] }
        return Array(collection)
    }

    private static func parseTime(_ node: ASN1Node) -> Date? {
        guard case let .primitive(bytes) = node.content else { return nil }
        let string = String(decoding: bytes, as: UTF8.self)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        // UTCTime = YYMMDDHHMMSSZ (13); GeneralizedTime = YYYYMMDDHHMMSSZ (15).
        formatter.dateFormat = string.count > 13 ? "yyyyMMddHHmmss'Z'" : "yyMMddHHmmss'Z'"
        return formatter.date(from: string)
    }

    /// SubjectKeyIdentifier ::= OCTET STRING, wrapped in the extension's OCTET STRING.
    private static func parseSKI(_ extnValue: [UInt8]) -> [UInt8]? {
        guard let inner = try? IDVSecurityObject.parseDERorBER(extnValue[...]),
              case let .primitive(keyId) = inner.content else { return nil }
        return Array(keyId)
    }

    /// AuthorityKeyIdentifier ::= SEQUENCE { keyIdentifier [0] OCTET STRING, ... }.
    private static func parseAKI(_ extnValue: [UInt8]) -> [UInt8]? {
        guard let seq = try? IDVSecurityObject.parseDERorBER(extnValue[...]),
              case let .constructed(fields) = seq.content else { return nil }
        for field in Array(fields)
            where field.identifier == ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific) {
            if case let .primitive(keyId) = field.content {
                return Array(keyId)
            }
        }
        return nil
    }
}
