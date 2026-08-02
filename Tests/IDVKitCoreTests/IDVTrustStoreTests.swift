//
//  IDVTrustStoreTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore
import Testing

struct IDVTrustStoreTests {
    @Test func certificatesDERArePreservedInOrder() {
        let der = [Data([0x30, 0x03, 0x02, 0x01, 0x00]), Data([0x30, 0x01, 0x00])]
        let store = IDVTrustStore(certificatesDER: der)
        #expect(store.anchorsDER == der)
    }

    @Test func nonCertificatePEMYieldsNoAnchors() {
        let store = IDVTrustStore(pem: "this is not a PEM certificate")
        #expect(store.anchorsDER.isEmpty)
    }

    @Test func emptyStoreHasNoAnchors() {
        #expect(IDVTrustStore(certificatesDER: []).anchorsDER.isEmpty)
    }

    @Test func missingPEMFileThrows() {
        #expect(throws: (any Error).self) {
            _ = try IDVTrustStore(pemFileURL: URL(fileURLWithPath: "/no/such/file.pem"))
        }
    }
}
