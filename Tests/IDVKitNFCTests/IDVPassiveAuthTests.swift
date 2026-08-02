//
//  IDVPassiveAuthTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Crypto
import Foundation
import IDVKitCore
@testable import IDVKitNFC
import Testing

/// A tiny DER builder for synthesizing test structures.
private enum DER {
    static func tlv(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        [tag] + length(value.count) + value
    }

    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 {
            return [UInt8(n)]
        }
        if n <= 0xFF {
            return [0x81, UInt8(n)]
        }
        return [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
    }

    static func integer(_ n: Int) -> [UInt8] {
        tlv(0x02, [UInt8(n)])
    }

    static func octetString(_ bytes: [UInt8]) -> [UInt8] {
        tlv(0x04, bytes)
    }

    static func sequence(_ children: [[UInt8]]) -> [UInt8] {
        tlv(0x30, children.flatMap(\.self))
    }

    /// OID 2.16.840.1.101.3.4.2.1 = SHA-256.
    static let sha256OID: [UInt8] = tlv(0x06, [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01])
}

struct LDSSecurityObjectTests {
    /// Builds a synthetic LDSSecurityObject with SHA-256 hashes for DG1 and DG2.
    private func makeLDS(dg1: [UInt8], dg2: [UInt8]) -> [UInt8] {
        DER.sequence([
            DER.integer(0), // version
            DER.sequence([DER.sha256OID]), // hashAlgorithm
            DER.sequence([ // dataGroupHashValues
                DER.sequence([DER.integer(1), DER.octetString(dg1)]),
                DER.sequence([DER.integer(2), DER.octetString(dg2)])
            ])
        ])
    }

    @Test func parsesHashAlgorithmAndHashes() throws {
        let dg1Hash = Array(SHA256.hash(data: [0xAA, 0xBB]))
        let dg2Hash = Array(SHA256.hash(data: [0xCC, 0xDD]))
        let lds = makeLDS(dg1: dg1Hash, dg2: dg2Hash)

        let parsed = try IDVSecurityObject.parseLDSSecurityObject(lds[...])
        #expect(parsed.hashAlgorithmOID.description == "2.16.840.1.101.3.4.2.1")
        #expect(parsed.hashes[1] == dg1Hash)
        #expect(parsed.hashes[2] == dg2Hash)
    }

    @Test func hashAlgorithmComputesCorrectDigest() {
        let data: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let expected = Array(SHA256.hash(data: data))
        #expect(IDVHashAlgorithm.sha256.digest(data) == expected)
        #expect(IDVHashAlgorithm(oid: "2.16.840.1.101.3.4.2.1") == .sha256)
        #expect(IDVHashAlgorithm(oid: "1.3.14.3.2.26") == .sha1)
    }

    @Test func dataGroupNumberMapping() {
        #expect(IDVSecurityObject.dataGroupNumber(.dg1) == 1)
        #expect(IDVSecurityObject.dataGroupNumber(.dg2) == 2)
        #expect(IDVSecurityObject.dataGroupNumber(.dg14) == 14)
        #expect(IDVSecurityObject.dataGroupNumber(.com) == nil)
        #expect(IDVSecurityObject.dataGroupNumber(.sod) == nil)
    }
}

struct SignatureAlgorithmMappingTests {
    @Test func mapsCommonPassportAlgorithms() {
        #expect(IDVSecurityObject.signatureAlgorithm(signatureOID: "1.2.840.10045.4.3.2", digestOID: "") != nil) // ECDSA-SHA256
        #expect(IDVSecurityObject.signatureAlgorithm(signatureOID: "1.2.840.113549.1.1.11", digestOID: "") != nil) // SHA256-RSA
        // Generic rsaEncryption resolves via the digest algorithm.
        #expect(IDVSecurityObject.signatureAlgorithm(signatureOID: "1.2.840.113549.1.1.1", digestOID: "2.16.840.1.101.3.4.2.1") != nil)
    }

    @Test func returnsNilForUnsupportedAlgorithms() {
        // RSA-PSS and ECDSA-SHA1 are not verifiable via swift-certificates — we
        // report "unsupported" honestly rather than a false negative.
        #expect(IDVSecurityObject.signatureAlgorithm(signatureOID: "1.2.840.113549.1.1.10", digestOID: "") == nil) // RSA-PSS
    }
}

struct TrustStoreTests {
    @Test func decodesConcatenatedPEM() {
        // Two trivial PEM blocks (payload need not be a real cert for decode).
        let payload = Data([0x30, 0x03, 0x02, 0x01, 0x05]).base64EncodedString()
        let pem = """
        -----BEGIN CERTIFICATE-----
        \(payload)
        -----END CERTIFICATE-----
        -----BEGIN CERTIFICATE-----
        \(payload)
        -----END CERTIFICATE-----
        """
        let store = IDVTrustStore(pem: pem)
        #expect(store.anchorsDER.count == 2)
    }

    @Test func emptyStoreHasNoAnchors() {
        #expect(IDVTrustStore.empty.anchorsDER.isEmpty)
    }
}

struct PassiveAuthenticatorTests {
    @Test func disabledReportsNotPerformed() {
        let authenticator = IDVPassiveAuthenticator(configuration: .disabled)
        let result = authenticator.verify(sod: [0x77, 0x00], dataGroups: [:])
        if case .notPerformed = result.dataIntegrity {} else {
            Issue.record("disabled should report notPerformed")
        }
    }

    @Test func malformedSODReportsFailedIntegrity() {
        let authenticator = IDVPassiveAuthenticator(configuration: .integrityOnly)
        let result = authenticator.verify(sod: [0x77, 0x02, 0x00, 0x00], dataGroups: [:])
        if case .failed = result.dataIntegrity {} else {
            Issue.record("a malformed SOD must fail integrity, not pass")
        }
        #expect(result.isFullyVerified == false)
    }
}
