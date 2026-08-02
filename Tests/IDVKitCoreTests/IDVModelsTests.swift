//
//  IDVModelsTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import IDVKitCore
import Testing

struct IDVCheckStatusTests {
    typealias Status = IDVChipAuthenticityResult.CheckStatus

    @Test func onlyPassedIsPassed() {
        #expect(Status.passed.isPassed)
        #expect(!Status.failed(reason: "x").isPassed)
        #expect(!Status.notPerformed(reason: "x").isPassed)
        #expect(!Status.notSupportedByChip.isPassed)
    }

    @Test func reasonIsPresentOnlyForFailureAndNotPerformed() {
        #expect(Status.failed(reason: "bad signature").reason == "bad signature")
        #expect(Status.notPerformed(reason: "no store").reason == "no store")
        #expect(Status.passed.reason == nil)
        #expect(Status.notSupportedByChip.reason == nil)
    }

    @Test func fullyVerifiedNeedsBothHalves() {
        let both = IDVPassiveAuthenticationResult(dataIntegrity: .passed, chainOfTrust: .passed)
        #expect(both.isFullyVerified)
        let integrityOnly = IDVPassiveAuthenticationResult(
            dataIntegrity: .passed, chainOfTrust: .notPerformed(reason: "no store")
        )
        #expect(!integrityOnly.isFullyVerified)
    }
}
