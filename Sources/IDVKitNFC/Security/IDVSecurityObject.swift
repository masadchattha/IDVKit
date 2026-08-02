//
//  IDVSecurityObject.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import _CryptoExtras
import Crypto
import Foundation
import IDVKitCore
import OSLog
import SwiftASN1
import X509

/// Parses EF.SOD — the eMRTD Document Security Object, a CMS SignedData
/// (RFC 5652) — and exposes the pieces passive authentication needs.
///
/// The CMS is hand-parsed with SwiftASN1: swift-certificates' `CMS` API is
/// SPI-gated and hardcodes `eContentType == id-data`, which every passport SOD
/// violates (SODs use the LDSSecurityObject OID). We extract the hash table,
/// the signer material, and the embedded Document Signer Certificate ourselves.
struct IDVSecurityObject {
    /// OID `2.23.136.1.1.1` — the LDSSecurityObject / SOD eContentType.
    private static let ldsSecurityObjectOID = ASN1ObjectIdentifier(arrayLiteral: 2, 23, 136, 1, 1, 1)
    /// OID `1.2.840.113549.1.9.4` — CMS messageDigest signed attribute.
    private static let messageDigestOID = ASN1ObjectIdentifier(arrayLiteral: 1, 2, 840, 113549, 1, 9, 4)

    /// The SOD's data-group hash algorithm.
    let hashAlgorithm: IDVHashAlgorithm
    /// dataGroupNumber → stored hash bytes.
    private let dataGroupHashes: [Int: [UInt8]]

    // Signature material.
    private let eContentBytes: [UInt8] // the DER LDSSecurityObject
    private let signedAttributesDER: [UInt8]? // re-tagged 0x31 SET, or nil if absent
    private let messageDigestInAttrs: [UInt8]?
    private let signatureBytes: [UInt8]
    private let signatureAlgorithmOID: String
    private let signerDigestOID: String
    private let pssHashOID: String?
    /// Every X.509 certificate embedded in the SOD; the DSC is whichever one
    /// verifies the signature and chains to a CSCA. May be empty when the DSC's
    /// key algorithm (e.g. id-RSASSA-PSS) is not parseable by swift-certificates.
    private let embeddedCertificates: [Certificate]
    /// RSA public keys extracted directly from the SOD (works for PSS keys).
    private let rsaPublicKeys: [_RSA.Signing.PublicKey]
    /// EC public keys extracted from the SOD (works for brainpool, which
    /// swift-certificates cannot parse).
    private let ecPublicKeys: [(curve: IDVEllipticCurve, point: IDVECPoint)]
    /// Raw DER of every embedded certificate (for IDVKit's own chain validation).
    private let certificateDERs: [[UInt8]]

    // MARK: Init / parse

    init(sodBytes: [UInt8]) throws {
        // Strip the outer application tag 0x77 wrapping the CMS ContentInfo.
        let contentInfoBytes = try Self.unwrapSOD(sodBytes)

        // ContentInfo → SignedData (BER-tolerant: ICAO permits non-DER).
        let root = try Self.parseDERorBER(contentInfoBytes[...])

        let parsed = try Self.parseSignedData(root)
        eContentBytes = parsed.eContent
        signedAttributesDER = parsed.signedAttributesDER
        messageDigestInAttrs = parsed.messageDigest
        signatureBytes = parsed.signature
        signatureAlgorithmOID = parsed.signatureAlgorithmOID
        signerDigestOID = parsed.digestAlgorithmOID
        pssHashOID = parsed.pssHashOID
        embeddedCertificates = parsed.certificates
        rsaPublicKeys = parsed.rsaPublicKeys
        ecPublicKeys = parsed.ecPublicKeys
        certificateDERs = parsed.certificateDERs

        // Parse the LDSSecurityObject out of the eContent.
        let lds = try Self.parseLDSSecurityObject(parsed.eContent[...])
        guard let algorithm = IDVHashAlgorithm(oid: lds.hashAlgorithmOID.description) else {
            throw IDVError.passiveAuthenticationFailed(detail: "unsupported SOD hash algorithm")
        }
        hashAlgorithm = algorithm
        dataGroupHashes = lds.hashes
    }

    // MARK: Data-group hashes

    /// The stored hash for a data group, if the SOD lists it.
    func hash(for group: IDVDataGroupID) -> [UInt8]? {
        guard let number = Self.dataGroupNumber(group) else { return nil }
        return dataGroupHashes[number]
    }

    // MARK: SOD signature verification

    /// Verifies the SOD's CMS signature (ICAO 9303 Part 11 §5.1 step 3):
    /// the DSC signs the SignedAttributes, whose messageDigest covers eContent.
    func verifySODSignature() throws -> Bool {
        // The signature is over the SignedAttributes (re-tagged as a SET), when
        // present; otherwise directly over the eContent.
        let signedData = signedAttributesDER ?? eContentBytes

        // If SignedAttributes are present, their messageDigest must equal the
        // hash of eContent — otherwise the signature covers attacker-chosen data.
        if signedAttributesDER != nil {
            guard let expectedDigest = messageDigestInAttrs else { return false }
            let digest = try digest(eContentBytes, oidString: signerDigestOID)
            guard digest == expectedDigest else { return false }
        }

        // RSA (PKCS#1 v1.5 and PSS) is verified via _CryptoExtras with the RSA
        // keys extracted straight from the SOD — this works even for id-RSASSA-PSS
        // keys that swift-certificates refuses to parse.
        if Self.isRSA(signatureAlgorithmOID) {
            return verifyRSASignature(over: signedData)
        }

        // ECDSA: try swift-certificates (NIST curves) first, then IDVKit's own
        // verifier for brainpool keys swift-certificates can't parse.
        if let algorithm = Self.signatureAlgorithm(signatureOID: signatureAlgorithmOID, digestOID: signerDigestOID) {
            for cert in embeddedCertificates
                where cert.publicKey.isValidSignature(signatureBytes, for: signedData, signatureAlgorithm: algorithm) {
                return true
            }
        }
        if let hash = Self.ecdsaHash(signatureOID: signatureAlgorithmOID, digestOID: signerDigestOID) {
            for key in ecPublicKeys where IDVActiveAuthentication.verifyECDSADER(
                signature: signatureBytes, message: signedData, hash: hash, curve: key.curve, publicKey: key.point
            ) {
                return true
            }
        }
        Logger.nfc.idvDebug("SOD: ECDSA (\(signatureAlgorithmOID)) not valid under \(embeddedCertificates.count) cert(s) / \(ecPublicKeys.count) EC key(s)")
        return false
    }

    /// Maps an ECDSA signature-algorithm OID (or the digest OID) to its hash.
    static func ecdsaHash(signatureOID: String, digestOID: String) -> IDVHashAlgorithm? {
        switch signatureOID {
        case "1.2.840.10045.4.1": .sha1 // ecdsa-with-SHA1
        case "1.2.840.10045.4.3.2": .sha256 // ecdsa-with-SHA256
        case "1.2.840.10045.4.3.3": .sha384 // ecdsa-with-SHA384
        case "1.2.840.10045.4.3.4": .sha512 // ecdsa-with-SHA512
        default: IDVHashAlgorithm(oid: digestOID)
        }
    }

    /// Verifies an RSA SOD signature (PKCS#1 v1.5 or PSS) against every RSA key
    /// extracted from the SOD.
    private func verifyRSASignature(over signedData: [UInt8]) -> Bool {
        let isPSS = signatureAlgorithmOID == Self.rsaPSSOID
        let padding: _RSA.Signing.Padding = isPSS ? .PSS : .insecurePKCS1v1_5
        // PSS uses the RSASSA-PSS-params hash; PKCS#1 uses the SignerInfo digest.
        let hashOID = isPSS ? (pssHashOID ?? "1.3.14.3.2.26") : signerDigestOID
        let signature = _RSA.Signing.RSASignature(rawRepresentation: Data(signatureBytes))

        for key in rsaPublicKeys {
            let valid: Bool = switch hashOID {
            case "2.16.840.1.101.3.4.2.1": key.isValidSignature(signature, for: SHA256.hash(data: signedData), padding: padding)
            case "2.16.840.1.101.3.4.2.2": key.isValidSignature(signature, for: SHA384.hash(data: signedData), padding: padding)
            case "2.16.840.1.101.3.4.2.3": key.isValidSignature(signature, for: SHA512.hash(data: signedData), padding: padding)
            case "1.3.14.3.2.26": key.isValidSignature(signature, for: Insecure.SHA1.hash(data: signedData), padding: padding)
            default: false
            }
            if valid {
                return true
            }
        }
        Logger.nfc.idvDebug("SOD: RSA \(isPSS ? "PSS" : "PKCS1") (hash \(hashOID)) not valid under any of \(rsaPublicKeys.count) key(s)")
        return false
    }

    /// Whether a signature-algorithm OID is one of the RSA schemes (PKCS#1 or PSS).
    static func isRSA(_ oid: String) -> Bool {
        oid == rsaPSSOID || oid.hasPrefix("1.2.840.113549.1.1.")
    }

    // MARK: DSC → CSCA chain

    /// Validates that the Document Signer Certificate chains to a trusted CSCA,
    /// using IDVKit's own X.509 verification so it works for brainpool keys.
    ///
    /// The DSC is matched to a CSCA by Authority/Subject Key Identifier (or by
    /// issuer/subject name), then the DSC's signature is verified under the CSCA
    /// public key. DSC expiry is not treated as a hard failure — passport DSCs
    /// routinely expire while the document is still valid (ICAO 9303 §5.1).
    func verifyChain(to trustStore: IDVTrustStore) -> IDVChipAuthenticityResult.CheckStatus {
        guard !trustStore.anchorsDER.isEmpty else {
            return .notPerformed(reason: "no CSCA trust store configured")
        }
        let cscas = trustStore.anchorsDER.compactMap { IDVX509Certificate(der: Array($0)) }
        guard !cscas.isEmpty else {
            return .failed(reason: "no valid CSCA certificates in trust store")
        }
        let dscs = certificateDERs.compactMap { IDVX509Certificate(der: $0) }
        guard !dscs.isEmpty else {
            return .notPerformed(reason: "Document Signer Certificate not embedded in SOD")
        }
        Logger.nfc.idvDebug("Chain of trust: \(cscas.count) CSCA(s) loaded, \(dscs.count) DSC(s) in SOD")
        var nameMatchedButUnverified = false
        for dsc in dscs {
            // RFC 5280 §6.1: a CSCA is a candidate issuer only when its subject
            // name (or Subject Key Identifier) matches the DSC's issuer name /
            // Authority Key Identifier. We verify the signature ONLY against those
            // candidates — never the whole store. Brute-forcing all anchors is both
            // wrong (RFC 5280) and catastrophically slow: a real master list holds
            // 500+ certs and each brainpool-EC verify costs ~0.3–0.8s, so an
            // unmatched DSC would hang the read for minutes.
            let candidates = cscas.filter { $0.isIssuer(of: dsc) || $0.subjectDER == dsc.issuerDER }
            if !candidates.isEmpty {
                nameMatchedButUnverified = true
            }
            Logger.nfc.idvDebug("Chain of trust: \(candidates.count) candidate CSCA(s) by issuer name/key")
            for csca in candidates where csca.hasSigned(dsc) {
                Logger.nfc.idvDebug("Chain of trust: DSC verified against a trusted CSCA")
                return .passed
            }
        }
        // Distinguish "issuing CSCA not in the store" from "matched but signature
        // failed" — the latter points at a parsing/algorithm bug, not a missing anchor.
        if nameMatchedButUnverified {
            return .failed(reason: "matched a CSCA by name but its signature did not verify")
        }
        // Surface exactly which CSCA the integrator needs to add. The DSC's issuer
        // is the missing anchor; include its name, country and key ID.
        if let dsc = dscs.first {
            var detail = "issuing CSCA not in trust store — add the CSCA for [\(dsc.issuerDescription)]"
            if let keyID = dsc.authorityKeyIdentifierHex {
                detail += ", key-ID \(keyID)"
            }
            return .failed(reason: detail)
        }
        return .failed(reason: "issuing country's CSCA is not in the trust store")
    }

    // MARK: Hashing

    private func digest(_ bytes: [UInt8], oidString: String) throws -> [UInt8] {
        guard let algorithm = IDVHashAlgorithm(oid: oidString) else {
            throw IDVError.passiveAuthenticationFailed(detail: "unsupported digest \(oidString)")
        }
        return algorithm.digest(bytes)
    }

    static func dataGroupNumber(_ group: IDVDataGroupID) -> Int? {
        switch group {
        case .dg1: 1
        case .dg2: 2
        case .dg7: 7
        case .dg11: 11
        case .dg12: 12
        case .dg14: 14
        case .dg15: 15
        case .com, .sod: nil
        }
    }
}
