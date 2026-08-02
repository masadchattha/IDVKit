//
//  IDVConfigurationTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

@testable import IDVKitCore
import Testing

struct IDVConfigurationTests {
    @Test func defaultConfigurationIsSane() {
        let config = IDVConfiguration.default
        #expect(config.steps == [.documentScan(.any), .nfcChipRead, .faceMatch])
        #expect(config.face.matchThreshold == 0.65)
        #expect(config.mrz.allowManualEntry)
        // Default verifies data integrity; full chain trust needs a host-supplied
        // CSCA store, so integrityOnly is the honest default.
        if case .integrityOnly = config.nfc.passiveAuthentication {
        } else {
            Issue.record("passive authentication should default to integrityOnly")
        }
    }

    @Test func loggingIsOffByDefault() {
        #expect(IDVLog.isEnabled == false)
    }

    @Test func brandingDefaultsToNeutral() {
        let branding = IDVBrandingConfiguration()
        #expect(branding.logoImageData == nil)
        #expect(branding.showsPoweredByBadge)
    }
}
