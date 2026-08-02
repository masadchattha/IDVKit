//
//  IDVSecurityObject+Parsing.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//
//  Hand-parsing of the SOD's CMS SignedData (RFC 5652) and the LDSSecurityObject
//  (ICAO 9303 Part 10). We navigate the ASN.1 tree directly so we can capture
//  exact original bytes — the SOD signature is verified over the precise
//  SignedAttributes encoding, which must never be round-tripped.
//

import _CryptoExtras
import Foundation
import OSLog
import SwiftASN1
import IDVKitCore
import X509

extension IDVSecurityObject {
    /// Recursively collects every node that parses as an X.509 `Certificate`.
    /// Used for ECDSA signature verification and DSC→CSCA chain validation.
    static func collectCertificates(_ node: ASN1Node) -> [Certificate] {
        var result: [Certificate] = []
        func walk(_ node: ASN1Node) {
            if let cert = try? Certificate(derEncoded: Array(node.encodedBytes)) {
                result.append(cert)
                return // don't descend into a parsed certificate
            }
            if case let .constructed(collection) = node.content {
                for child in collection {
                    walk(child)
                }
            }
        }
        walk(node)
        return result
    }

    /// Recursively collects every RSA public key by finding SubjectPublicKeyInfo
    /// blocks — `SEQUENCE { AlgorithmIdentifier, BIT STRING }` — and building an
    /// `_RSA.Signing.PublicKey` from each. Unlike swift-certificates, this works
    /// even when the key algorithm is `id-RSASSA-PSS` (the DER initializer strips
    /// the PSS parameters), which is exactly what fails to parse otherwise.
    static func collectRSAPublicKeys(_ node: ASN1Node) -> [_RSA.Signing.PublicKey] {
        var keys: [_RSA.Signing.PublicKey] = []
        var seen: Set<[UInt8]> = []
        func walk(_ node: ASN1Node) {
            // A SubjectPublicKeyInfo is SEQUENCE { AlgorithmIdentifier, BIT STRING }.
            if node.identifier == .sequence, case let .constructed(collection) = node.content {
                let children = Array(collection)
                if children.count == 2,
                   children[0].identifier == .sequence,
                   children[1].identifier == .bitString {
                    let spki = Array(node.encodedBytes)
                    if seen.insert(spki).inserted,
                       let key = rsaKey(algorithm: children[0], bitString: children[1]) {
                        keys.append(key)
                    }
                }
            }
            // Descend into EVERY constructed node — including CMS context tags
            // like `certificates [0]`, which wrap the certificate (and its SPKI).
            if case let .constructed(collection) = node.content {
                for child in collection {
                    walk(child)
                }
            }
        }
        walk(node)
        return keys
    }

    /// Recursively collects the raw DER of every embedded X.509 certificate
    /// (structurally `SEQUENCE { SEQUENCE tbs, SEQUENCE sigAlg, BIT STRING sig }`),
    /// so IDVKit can parse brainpool certificates swift-certificates rejects.
    static func collectCertificateDERs(_ node: ASN1Node) -> [[UInt8]] {
        var result: [[UInt8]] = []
        func walk(_ node: ASN1Node) {
            if node.identifier == .sequence, case let .constructed(collection) = node.content {
                let children = Array(collection)
                if children.count == 3,
                   children[0].identifier == .sequence,
                   children[1].identifier == .sequence,
                   children[2].identifier == .bitString {
                    result.append(Array(node.encodedBytes))
                    return // a certificate — don't descend
                }
            }
            if case let .constructed(collection) = node.content {
                for child in collection {
                    walk(child)
                }
            }
        }
        walk(node)
        return result
    }

    /// Recursively collects EC public keys (curve + point) from SPKI blocks.
    /// Uses IDVKit's own curve math, so it handles brainpool curves that
    /// swift-certificates cannot parse — which is how many countries' Document
    /// Signer Certificates (and this passport's) are keyed.
    static func collectECPublicKeys(_ node: ASN1Node) -> [(curve: IDVEllipticCurve, point: IDVECPoint)] {
        var result: [(IDVEllipticCurve, IDVECPoint)] = []
        var seen: Set<[UInt8]> = []
        func walk(_ node: ASN1Node) {
            if node.identifier == .sequence, case let .constructed(collection) = node.content {
                let children = Array(collection)
                if children.count == 2,
                   children[0].identifier == .sequence,
                   children[1].identifier == .bitString,
                   let keyPair = ecKey(algorithm: children[0], bitString: children[1]),
                   seen.insert(Array(node.encodedBytes)).inserted {
                    result.append(keyPair)
                }
            }
            if case let .constructed(collection) = node.content {
                for child in collection {
                    walk(child)
                }
            }
        }
        walk(node)
        return result
    }

    private static func ecKey(algorithm algNode: ASN1Node, bitString bitStringNode: ASN1Node) -> (IDVEllipticCurve, IDVECPoint)? {
        guard case let .constructed(alg) = algNode.content else { return nil }
        let algItems = Array(alg)
        guard algItems.count >= 2,
              let oid = try? ASN1ObjectIdentifier(derEncoded: algItems[0]),
              oid.description == "1.2.840.10045.2.1", // id-ecPublicKey
              let curve = IDVECParameters.curve(fromParameters: algItems[1]),
              let bits = try? ASN1BitString(derEncoded: bitStringNode),
              let point = curve.decodePoint(Array(bits.bytes)) else { return nil }
        return (curve, point)
    }

    /// Builds an RSA public key from a SubjectPublicKeyInfo by parsing the
    /// modulus and exponent directly, then using `init(n:e:)`. This avoids the
    /// SPKI-level DER path entirely, so it works for `id-RSASSA-PSS` keys (which
    /// carry parameters that trip other loaders) and never traps on odd input.
    private static func rsaKey(algorithm algNode: ASN1Node, bitString bitStringNode: ASN1Node) -> _RSA.Signing.PublicKey? {
        // Only RSA keys: rsaEncryption or id-RSASSA-PSS.
        guard case let .constructed(alg) = algNode.content,
              let oidNode = Array(alg).first,
              let oid = try? ASN1ObjectIdentifier(derEncoded: oidNode),
              oid.description == "1.2.840.113549.1.1.1" || oid.description == "1.2.840.113549.1.1.10" else {
            return nil
        }
        // The BIT STRING wraps RSAPublicKey ::= SEQUENCE { modulus, exponent }.
        guard let bits = try? ASN1BitString(derEncoded: bitStringNode),
              let rsaKeySeq = try? parseDERorBER(bits.bytes),
              case let .constructed(parts) = rsaKeySeq.content else { return nil }
        let items = Array(parts)
        guard items.count == 2,
              case let .primitive(modulus) = items[0].content,
              case let .primitive(exponent) = items[1].content else { return nil }
        // Pass the unsigned big-endian magnitudes.
        let n = modulus.first == 0x00 ? Array(modulus.dropFirst()) : Array(modulus)
        let e = exponent.first == 0x00 ? Array(exponent.dropFirst()) : Array(exponent)
        return try? _RSA.Signing.PublicKey(n: n, e: e)
    }

    /// The fields extracted from a CMS SignedData needed for verification.
    struct ParsedSignedData {
        let eContent: [UInt8]
        let signedAttributesDER: [UInt8]? // re-tagged as SET (0x31), or nil
        let messageDigest: [UInt8]?
        let signature: [UInt8]
        let signatureAlgorithmOID: String
        let digestAlgorithmOID: String
        /// For RSASSA-PSS signatures, the hash OID from RSASSA-PSS-params.
        let pssHashOID: String?
        let certificates: [Certificate]
        /// RSA public keys extracted directly from SPKI blocks, for RSA
        /// verification when swift-certificates can't parse the certificate.
        let rsaPublicKeys: [_RSA.Signing.PublicKey]
        /// EC public keys (curve + point), for ECDSA verification of brainpool
        /// keys swift-certificates can't parse.
        let ecPublicKeys: [(curve: IDVEllipticCurve, point: IDVECPoint)]
        /// Raw DER of every embedded certificate, for IDVKit's own chain
        /// validation (handles brainpool).
        let certificateDERs: [[UInt8]]
    }

    /// OID of the RSASSA-PSS signature algorithm.
    static let rsaPSSOID = "1.2.840.113549.1.1.10"

    // MARK: SOD unwrap

    /// Strips the outer application tag `0x77` that wraps the CMS ContentInfo.
    static func unwrapSOD(_ sodBytes: [UInt8]) throws -> [UInt8] {
        let root = try IDVBERTLV.parse(sodBytes).tlv
        guard root.tag.first == 0x77 else {
            // Some readers hand us the ContentInfo directly.
            return sodBytes
        }
        return root.value
    }

    // MARK: ASN.1 navigation helpers

    /// Parses strict DER, falling back to lenient BER (ICAO permits BER).
    static func parseDERorBER(_ bytes: ArraySlice<UInt8>) throws -> ASN1Node {
        if let der = try? DER.parse(bytes) {
            return der
        }
        return try BER.parse(bytes)
    }

    private static func children(_ node: ASN1Node) -> [ASN1Node] {
        guard case let .constructed(collection) = node.content else { return [] }
        return Array(collection)
    }

    private static func primitiveBytes(_ node: ASN1Node) -> [UInt8]? {
        guard case let .primitive(bytes) = node.content else { return nil }
        return Array(bytes)
    }

    private static func isContextTag(_ node: ASN1Node, _ number: UInt) -> Bool {
        node.identifier == ASN1Identifier(tagWithNumber: number, tagClass: .contextSpecific)
    }

    /// Reads the algorithm OID from an `AlgorithmIdentifier ::= SEQUENCE { OID, params? }`.
    private static func algorithmOID(_ node: ASN1Node) throws -> String {
        guard let first = children(node).first,
              let oid = try? ASN1ObjectIdentifier(derEncoded: first) else {
            throw IDVError.passiveAuthenticationFailed(detail: "malformed AlgorithmIdentifier")
        }
        return oid.description
    }

    // MARK: SignedData

    /// Parses a CMS `ContentInfo`/`SignedData` into the fields we verify.
    static func parseSignedData(_ contentInfo: ASN1Node) throws -> ParsedSignedData {
        // ContentInfo ::= SEQUENCE { contentType OID, content [0] EXPLICIT SignedData }
        let contentInfoChildren = children(contentInfo)
        guard contentInfoChildren.count >= 2,
              let contentZero = contentInfoChildren.last,
              let signedData = children(contentZero).first else {
            throw IDVError.passiveAuthenticationFailed(detail: "malformed CMS ContentInfo")
        }

        // SignedData ::= SEQUENCE { version, digestAlgorithms SET, encapContentInfo,
        //                           certificates [0] IMPLICIT OPTIONAL, crls [1]?, signerInfos SET }
        let sd = children(signedData)
        guard sd.count >= 4 else {
            throw IDVError.passiveAuthenticationFailed(detail: "malformed CMS SignedData")
        }

        // encapContentInfo ::= SEQUENCE { eContentType OID, eContent [0] EXPLICIT OCTET STRING }
        guard let encap = sd.first(where: { $0.identifier == .sequence && children($0).count >= 2 }) else {
            throw IDVError.passiveAuthenticationFailed(detail: "missing encapContentInfo")
        }
        let encapChildren = children(encap)
        guard let eContentZero = encapChildren.last,
              let octet = children(eContentZero).first,
              let eContent = primitiveBytes(octet) else {
            throw IDVError.passiveAuthenticationFailed(detail: "missing eContent")
        }

        // Collect every embedded X.509 certificate by walking the whole
        // SignedData. Positional `certificates [0]` navigation is fragile across
        // issuers; the DSC is whichever embedded cert verifies the signature and
        // chains to a CSCA, so we gather them all and try each.
        let certificates = collectCertificates(signedData)
        let rsaPublicKeys = collectRSAPublicKeys(signedData)
        let ecPublicKeys = collectECPublicKeys(signedData)
        let rawCertDERs = collectCertificateDERs(signedData)
        // `certificates` = swift-certificates parse (always 0 for brainpool);
        // `rawCert` = IDVKit's own DER collection, which is what chain-of-trust
        // actually uses. The two differ exactly when the DSC is brainpool.
        Logger.nfc.idvDebug("SOD: \(certificates.count) X509 cert(s), \(rawCertDERs.count) raw cert DER(s), \(rsaPublicKeys.count) RSA + \(ecPublicKeys.count) EC key(s)")
        guard !certificates.isEmpty || !rsaPublicKeys.isEmpty || !ecPublicKeys.isEmpty else {
            throw IDVError.passiveAuthenticationFailed(detail: "SOD contains no Document Signer Certificate")
        }

        // signerInfos SET OF SignerInfo — take the first.
        guard let signerInfos = sd.last(where: { $0.identifier == .set }),
              let signerInfo = children(signerInfos).first else {
            throw IDVError.passiveAuthenticationFailed(detail: "missing SignerInfo")
        }
        let si = children(signerInfo)

        // SignerInfo ::= SEQUENCE { version INT, sid, digestAlgorithm,
        //   signedAttrs [0] IMPLICIT OPTIONAL, signatureAlgorithm, signature OCTET STRING, ... }
        // The `sid` (issuerAndSerialNumber) is itself a SEQUENCE, so fields must
        // be located by position, not by "first SEQUENCE".
        guard si.count >= 5 else {
            throw IDVError.passiveAuthenticationFailed(detail: "malformed SignerInfo")
        }
        // digestAlgorithm is the 3rd element (after version and sid).
        let digestOID = try algorithmOID(si[2])

        // signedAttrs [0] IMPLICIT — capture bytes and re-tag 0xA0 → 0x31 (SET).
        var signedAttributesDER: [UInt8]?
        var messageDigest: [UInt8]?
        if let attrsNode = si.first(where: { isContextTag($0, 0) }) {
            var bytes = Array(attrsNode.encodedBytes)
            if !bytes.isEmpty {
                bytes[0] = 0x31
            } // SET OF
            signedAttributesDER = bytes
            messageDigest = extractMessageDigest(attrsNode)
        }

        // The signature is the OCTET STRING; signatureAlgorithm is the SEQUENCE
        // immediately before it.
        guard let sigIndex = si.lastIndex(where: { $0.identifier == .octetString }),
              let signature = primitiveBytes(si[sigIndex]) else {
            throw IDVError.passiveAuthenticationFailed(detail: "missing SignerInfo signature")
        }
        let signatureAlgNode = si[..<sigIndex].last(where: { $0.identifier == .sequence })
        let signatureOID = try signatureAlgNode.map { try algorithmOID($0) } ?? ""
        let pssHashOID: String? = signatureOID == rsaPSSOID
            ? signatureAlgNode.map(pssParameterHashOID) : nil

        return ParsedSignedData(
            eContent: eContent,
            signedAttributesDER: signedAttributesDER,
            messageDigest: messageDigest,
            signature: signature,
            signatureAlgorithmOID: signatureOID,
            digestAlgorithmOID: digestOID,
            pssHashOID: pssHashOID,
            certificates: certificates,
            rsaPublicKeys: rsaPublicKeys,
            ecPublicKeys: ecPublicKeys,
            certificateDERs: rawCertDERs
        )
    }

    /// Extracts the hash OID from an RSASSA-PSS AlgorithmIdentifier's parameters.
    /// `RSASSA-PSS-params ::= SEQUENCE { hashAlgorithm [0] AlgorithmIdentifier
    /// DEFAULT sha1, ... }`. Defaults to SHA-1 when the parameter is absent.
    static func pssParameterHashOID(_ algNode: ASN1Node) -> String {
        let sha1 = "1.3.14.3.2.26"
        let kids = children(algNode)
        guard kids.count >= 2 else { return sha1 }
        let params = kids[1] // RSASSA-PSS-params SEQUENCE
        guard let hashTag = children(params).first(where: { isContextTag($0, 0) }),
              let algId = children(hashTag).first,
              let oidNode = children(algId).first,
              let oid = try? ASN1ObjectIdentifier(derEncoded: oidNode) else {
            return sha1
        }
        return oid.description
    }

    /// Finds the `messageDigest` (OID 1.2.840.113549.1.9.4) attribute value in
    /// a SignedAttributes node.
    private static func extractMessageDigest(_ attrsNode: ASN1Node) -> [UInt8]? {
        let target = ASN1ObjectIdentifier(arrayLiteral: 1, 2, 840, 113549, 1, 9, 4)
        // Each Attribute ::= SEQUENCE { attrType OID, attrValues SET OF ANY }.
        for attr in children(attrsNode) {
            let parts = children(attr)
            guard let typeNode = parts.first,
                  let oid = try? ASN1ObjectIdentifier(derEncoded: typeNode),
                  oid == target,
                  let valueSet = parts.last,
                  let valueNode = children(valueSet).first,
                  case let .primitive(bytes) = valueNode.content else { continue }
            return Array(bytes)
        }
        return nil
    }

    // MARK: LDSSecurityObject

    struct ParsedLDS {
        let hashAlgorithmOID: ASN1ObjectIdentifier
        let hashes: [Int: [UInt8]]
    }

    /// Parses `LDSSecurityObject ::= SEQUENCE { version, hashAlgorithm,
    /// SEQUENCE OF DataGroupHash { dgNumber INTEGER, hash OCTET STRING }, ... }`.
    static func parseLDSSecurityObject(_ der: ArraySlice<UInt8>) throws -> ParsedLDS {
        let root = try parseDERorBER(der)
        let top = children(root)
        guard top.count >= 3 else {
            throw IDVError.passiveAuthenticationFailed(detail: "malformed LDSSecurityObject")
        }
        // top[0] = version INTEGER, top[1] = hashAlgorithm AlgorithmIdentifier,
        // top[2] = SEQUENCE OF DataGroupHash.
        let hashAlgNode = top[1]
        guard let algOIDNode = children(hashAlgNode).first,
              let hashOID = try? ASN1ObjectIdentifier(derEncoded: algOIDNode) else {
            throw IDVError.passiveAuthenticationFailed(detail: "missing LDS hash algorithm")
        }

        var hashes: [Int: [UInt8]] = [:]
        for entry in children(top[2]) {
            let pair = children(entry)
            guard pair.count >= 2,
                  let numberNode = pair.first,
                  let number = try? Int(derEncoded: numberNode),
                  case let .primitive(hashBytes) = pair[1].content else { continue }
            hashes[number] = Array(hashBytes)
        }
        return ParsedLDS(hashAlgorithmOID: hashOID, hashes: hashes)
    }

    // MARK: Signature-algorithm mapping

    /// Maps a SignerInfo signature-algorithm OID (plus digest OID for generic
    /// RSA) to a `Certificate.SignatureAlgorithm`. Returns `nil` for algorithms
    /// swift-certificates cannot verify (RSA-PSS, ECDSA-SHA1) — the caller then
    /// reports an honest "unsupported" rather than a false negative.
    static func signatureAlgorithm(signatureOID: String, digestOID: String) -> Certificate.SignatureAlgorithm? {
        switch signatureOID {
        case "1.2.840.10045.4.3.2": .ecdsaWithSHA256
        case "1.2.840.10045.4.3.3": .ecdsaWithSHA384
        case "1.2.840.10045.4.3.4": .ecdsaWithSHA512
        case "1.2.840.113549.1.1.5": .sha1WithRSAEncryption
        case "1.2.840.113549.1.1.11": .sha256WithRSAEncryption
        case "1.2.840.113549.1.1.12": .sha384WithRSAEncryption
        case "1.2.840.113549.1.1.13": .sha512WithRSAEncryption
        case "1.2.840.113549.1.1.1": // generic rsaEncryption → pick by digest
            switch digestOID {
            case "1.3.14.3.2.26": .sha1WithRSAEncryption
            case "2.16.840.1.101.3.4.2.1": .sha256WithRSAEncryption
            case "2.16.840.1.101.3.4.2.2": .sha384WithRSAEncryption
            case "2.16.840.1.101.3.4.2.3": .sha512WithRSAEncryption
            default: nil
            }
        default:
            nil // RSA-PSS (1.1.10), ECDSA-SHA1, etc.
        }
    }
}
