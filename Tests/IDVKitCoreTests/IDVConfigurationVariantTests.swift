//
//  IDVConfigurationVariantTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import IDVKitCore
import Testing

struct IDVConfigurationVariantTests {
    @Test func mrzDefaultsAreDocumentAgnostic() {
        let mrz = IDVMRZConfiguration()
        #expect(mrz.documentKind == .any)
        #expect(mrz.showsTorchButton)
        #expect(mrz.allowManualEntry)
    }

    @Test func faceDefaultsAreProductionSane() {
        let face = IDVFaceConfiguration()
        #expect(face.matchThreshold == 0.65)
        #expect(face.allowsDebugPhotoMatch == false)
    }

    @Test func uiHidesSecurityDetailsByDefault() {
        let ui = IDVUIConfiguration()
        #expect(ui.showsSecurityDetails == false)
        #expect(ui.showDataReview)
    }

    @Test func defaultFlowRunsAllThreeSteps() {
        let steps = IDVConfiguration.default.steps
        #expect(steps.contains(.nfcChipRead))
        #expect(steps.contains(.faceMatch))
    }

    // MARK: Document picker

    @Test func defaultOffersNoDocumentChoice() {
        let mrz = IDVMRZConfiguration()
        #expect(mrz.allowedDocuments == [.any])
        #expect(mrz.selectableDocuments.isEmpty)
        #expect(mrz.offersDocumentChoice == false)
    }

    @Test func singleConcreteKindShowsNoPicker() {
        let mrz = IDVMRZConfiguration(allowedDocuments: [.passport])
        #expect(mrz.selectableDocuments == [.passport])
        #expect(mrz.offersDocumentChoice == false)
    }

    @Test func twoOrMoreKindsOfferAChoice() {
        let mrz = IDVMRZConfiguration(allowedDocuments: [.passport, .idCard])
        #expect(mrz.offersDocumentChoice)
        #expect(mrz.selectableDocuments == [.passport, .idCard])
    }

    @Test func selectableDropsAnyAndDeduplicatesPreservingOrder() {
        let mrz = IDVMRZConfiguration(
            allowedDocuments: [.idCard, .any, .passport, .idCard, .residencePermit]
        )
        #expect(mrz.selectableDocuments == [.idCard, .passport, .residencePermit])
        #expect(mrz.offersDocumentChoice)
    }
}
