//
//  VIDConfigurationTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Testing
@testable import VerifIDCore

@Suite struct VIDConfigurationTests {
    @Test func defaultConfigurationIsSane() {
        let config = VIDConfiguration.default
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
        #expect(VIDLog.isEnabled == false)
    }

    @Test func brandingDefaultsToNeutral() {
        let branding = VIDBrandingConfiguration()
        #expect(branding.logoImageData == nil)
        #expect(branding.showsPoweredByBadge)
    }
}
