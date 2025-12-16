//
//  VIDTrustStoreTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation
import Testing
import VerifIDCore

struct VIDTrustStoreTests {
    @Test func certificatesDERArePreservedInOrder() {
        let der = [Data([0x30, 0x03, 0x02, 0x01, 0x00]), Data([0x30, 0x01, 0x00])]
        let store = VIDTrustStore(certificatesDER: der)
        #expect(store.anchorsDER == der)
    }

    @Test func nonCertificatePEMYieldsNoAnchors() {
        let store = VIDTrustStore(pem: "this is not a PEM certificate")
        #expect(store.anchorsDER.isEmpty)
    }

    @Test func emptyStoreHasNoAnchors() {
        #expect(VIDTrustStore(certificatesDER: []).anchorsDER.isEmpty)
    }

    @Test func missingPEMFileThrows() {
        #expect(throws: (any Error).self) {
            _ = try VIDTrustStore(pemFileURL: URL(fileURLWithPath: "/no/such/file.pem"))
        }
    }
}
