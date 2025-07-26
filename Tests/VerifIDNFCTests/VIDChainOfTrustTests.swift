//
//  VIDChainOfTrustTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 11/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Crypto
import Foundation
import SwiftASN1
import Testing
import VerifIDCore
@testable import VerifIDNFC
import X509

/// Exercises VerifID's own X.509 parser + DSC→CSCA verification against real,
/// freshly-minted certificates (a CSCA-like CA and a DSC-like leaf it signs).
/// The brainpool ECDSA math itself is covered by `ECDSADERVerificationTests`;
/// this proves the certificate parsing, issuer matching, and signature check
/// wire together correctly.
struct ChainOfTrustTests {
    /// A CA that signs a leaf: the leaf must verify against the CA, and not
    /// against an unrelated CA or against itself.
    @Test func leafVerifiesAgainstItsIssuerOnly() throws {
        let ca = try makeCA(commonName: "VerifID Test CSCA")
        let stranger = try makeCA(commonName: "Some Other CSCA")
        let leaf = try makeLeaf(commonName: "VerifID Test DSC", issuer: ca)

        let caCert = try #require(VIDX509Certificate(der: der(ca.certificate)))
        let strangerCert = try #require(VIDX509Certificate(der: der(stranger.certificate)))
        let leafCert = try #require(VIDX509Certificate(der: der(leaf)))

        // The real security gate: the CA's key verifies the leaf's signature.
        #expect(caCert.hasSigned(leafCert))
        // An unrelated CA must not verify it.
        #expect(!strangerCert.hasSigned(leafCert))
        // A self-signed CA verifies itself; the leaf did not sign itself.
        #expect(caCert.hasSigned(caCert))
        #expect(!leafCert.hasSigned(leafCert))
    }

    /// Issuer matching should hold both by name and by AKI→SKI.
    @Test func issuerMatchingByNameAndKeyIdentifier() throws {
        let ca = try makeCA(commonName: "VerifID Test CSCA")
        let leaf = try makeLeaf(commonName: "VerifID Test DSC", issuer: ca)

        let caCert = try #require(VIDX509Certificate(der: der(ca.certificate)))
        let leafCert = try #require(VIDX509Certificate(der: der(leaf)))

        #expect(caCert.isIssuer(of: leafCert))
        // The leaf's AKI must equal the CA's SKI.
        #expect(leafCert.authorityKeyIdentifier != nil)
        #expect(leafCert.authorityKeyIdentifier == caCert.subjectKeyIdentifier)
        // Inner/outer signature algorithms agree.
        #expect(leafCert.algorithmConsistent)
    }

    /// A master-list PEM/DER round-trips into a usable trust store.
    @Test func trustStoreFromDERCertificates() throws {
        let ca = try makeCA(commonName: "VerifID Test CSCA")
        let store = try VIDTrustStore(certificatesDER: [Data(der(ca.certificate))])
        #expect(store.anchorsDER.count == 1)
        #expect(VIDX509Certificate(der: Array(store.anchorsDER[0])) != nil)
    }

    /// A CscaMasterList CMS (the `.ml` format) yields its member CSCAs, and the
    /// resulting trust store verifies a DSC that one of them signed.
    @Test func masterListCMSYieldsAnchorsThatVerifyDSC() throws {
        let ca1 = try makeCA(commonName: "VerifID Test CSCA One")
        let ca2 = try makeCA(commonName: "VerifID Test CSCA Two")
        let cms = try masterListCMS(certs: [ca1.certificate, ca2.certificate])

        let anchors = VIDCSCAMasterList.certificateDERs(fromCMS: cms)
        #expect(anchors.count == 2)

        // The extracted anchors must be the very certificates we embedded — and
        // one of them must verify a DSC it signed.
        let leaf = try makeLeaf(commonName: "VerifID Test DSC", issuer: ca1)
        let leafCert = try #require(VIDX509Certificate(der: der(leaf)))
        let anchorCerts = anchors.compactMap { VIDX509Certificate(der: Array($0)) }
        #expect(anchorCerts.contains { $0.hasSigned(leafCert) })
    }

    /// Assembles a minimal `ContentInfo → SignedData → CscaMasterList` around the
    /// given certificates — enough to exercise the real navigation path.
    private func masterListCMS(certs: [Certificate]) throws -> [UInt8] {
        let certDERs = try certs.map { try der($0) }
        // CscaMasterList ::= SEQUENCE { version INTEGER 0, certList SET OF Certificate }
        let certList = derTLV(0x31, certDERs.flatMap(\.self)) // SET OF
        let masterList = derTLV(0x30, derTLV(0x02, [0x00]) + certList)
        // encapContentInfo ::= SEQUENCE { eContentType OID, eContent [0] OCTET STRING }
        let mlOID: [UInt8] = [0x06, 0x06, 0x67, 0x81, 0x08, 0x01, 0x01, 0x02] // 2.23.136.1.1.2
        let eContent = derTLV(0xA0, derTLV(0x04, masterList))
        let encap = derTLV(0x30, mlOID + eContent)
        // SignedData ::= SEQUENCE { version INTEGER 3, digestAlgorithms SET, encap, ... }
        let signedData = derTLV(0x30, derTLV(0x02, [0x03]) + derTLV(0x31, []) + encap)
        // ContentInfo ::= SEQUENCE { contentType OID signedData, [0] EXPLICIT SignedData }
        let sdOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]
        return derTLV(0x30, sdOID + derTLV(0xA0, signedData))
    }

    /// Emits a DER TLV with correct short/long-form length encoding.
    private func derTLV(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [tag]
        let n = value.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else {
            var lengthBytes: [UInt8] = []
            var remaining = n
            while remaining > 0 {
                lengthBytes.insert(UInt8(remaining & 0xFF), at: 0); remaining >>= 8
            }
            out.append(0x80 | UInt8(lengthBytes.count))
            out.append(contentsOf: lengthBytes)
        }
        out.append(contentsOf: value)
        return out
    }

    // MARK: Fixtures

    private struct CA {
        let certificate: Certificate
        let privateKey: Certificate.PrivateKey
        let name: DistinguishedName
    }

    /// The DSC's issuer (the missing CSCA) is surfaced in a readable form so an
    /// integrator knows exactly which anchor to add.
    @Test func exposesIssuerIdentityForMissingAnchor() throws {
        let ca = try makeCA(commonName: "CSCAPKI_TEST")
        let leaf = try makeLeaf(commonName: "DSCAPKI_TEST", issuer: ca)
        let leafCert = try #require(VIDX509Certificate(der: der(leaf)))

        #expect(leafCert.issuerDescription.contains("CN=CSCAPKI_TEST"))
        #expect(leafCert.issuerDescription.contains("C=PK"))
        #expect(leafCert.issuerCountry == "PK")
        // The AKI (issuing CSCA key ID) is exposed as hex for the integrator.
        #expect(leafCert.authorityKeyIdentifierHex?.isEmpty == false)
    }

    private func makeCA(commonName: String) throws -> CA {
        let key = P256.Signing.PrivateKey()
        let name = try DistinguishedName { CommonName(commonName); CountryName("PK") }
        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            SubjectKeyIdentifier(hash: Certificate.PublicKey(key.publicKey))
        }
        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(key.publicKey),
            notValidBefore: Date().addingTimeInterval(-3600),
            notValidAfter: Date().addingTimeInterval(3600 * 24 * 365),
            issuer: name, subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(key)
        )
        return CA(certificate: cert, privateKey: Certificate.PrivateKey(key), name: name)
    }

    private func makeLeaf(commonName: String, issuer: CA) throws -> Certificate {
        let key = P256.Signing.PrivateKey()
        let subject = try DistinguishedName { CommonName(commonName) }
        let issuerSKI = try SubjectKeyIdentifier(hash: issuer.certificate.publicKey)
        let extensions = try Certificate.Extensions {
            SubjectKeyIdentifier(hash: Certificate.PublicKey(key.publicKey))
            AuthorityKeyIdentifier(keyIdentifier: issuerSKI.keyIdentifier)
        }
        return try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(key.publicKey),
            notValidBefore: Date().addingTimeInterval(-3600),
            notValidAfter: Date().addingTimeInterval(3600 * 24 * 365),
            issuer: issuer.name, subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: issuer.privateKey
        )
    }

    private func der(_ certificate: Certificate) throws -> [UInt8] {
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        return serializer.serializedBytes
    }
}
