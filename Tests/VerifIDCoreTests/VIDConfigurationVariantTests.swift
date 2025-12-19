//
//  VIDConfigurationVariantTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Testing
import VerifIDCore

struct VIDConfigurationVariantTests {
    @Test func mrzDefaultsAreDocumentAgnostic() {
        let mrz = VIDMRZConfiguration()
        #expect(mrz.documentKind == .any)
        #expect(mrz.showsTorchButton)
        #expect(mrz.allowManualEntry)
    }

    @Test func faceDefaultsAreProductionSane() {
        let face = VIDFaceConfiguration()
        #expect(face.matchThreshold == 0.65)
        #expect(face.allowsDebugPhotoMatch == false)
    }

    @Test func uiHidesSecurityDetailsByDefault() {
        let ui = VIDUIConfiguration()
        #expect(ui.showsSecurityDetails == false)
        #expect(ui.showDataReview)
    }

    @Test func defaultFlowRunsAllThreeSteps() {
        let steps = VIDConfiguration.default.steps
        #expect(steps.contains(.nfcChipRead))
        #expect(steps.contains(.faceMatch))
    }

    // MARK: Document picker

    @Test func defaultOffersNoDocumentChoice() {
        let mrz = VIDMRZConfiguration()
        #expect(mrz.allowedDocuments == [.any])
        #expect(mrz.selectableDocuments.isEmpty)
        #expect(mrz.offersDocumentChoice == false)
    }

    @Test func singleConcreteKindShowsNoPicker() {
        let mrz = VIDMRZConfiguration(allowedDocuments: [.passport])
        #expect(mrz.selectableDocuments == [.passport])
        #expect(mrz.offersDocumentChoice == false)
    }

    @Test func twoOrMoreKindsOfferAChoice() {
        let mrz = VIDMRZConfiguration(allowedDocuments: [.passport, .idCard])
        #expect(mrz.offersDocumentChoice)
        #expect(mrz.selectableDocuments == [.passport, .idCard])
    }

    @Test func selectableDropsAnyAndDeduplicatesPreservingOrder() {
        let mrz = VIDMRZConfiguration(
            allowedDocuments: [.idCard, .any, .passport, .idCard, .residencePermit]
        )
        #expect(mrz.selectableDocuments == [.idCard, .passport, .residencePermit])
        #expect(mrz.offersDocumentChoice)
    }
}
