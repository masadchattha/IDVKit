//
//  VIDErrorTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation
import Testing
import VerifIDCore

@Suite struct VIDErrorTests {
    /// Every error must surface a non-empty, user-presentable description.
    @Test func everyErrorHasADescription() {
        let errors: [VIDError] = [
            .mrzScanTimeout,
            .mrzInvalidFormat(detail: "bad"),
            .mrzChecksumFailed(field: "documentNumber"),
            .nfcNotSupported,
            .nfcTagConnectionLost,
            .nfcSessionFailed(detail: "x"),
            .cameraPermissionDenied,
            .faceTrackingUnsupported,
            .livenessTimeout,
            .noFaceDetected(inImage: "live"),
            .multipleFacesDetected(inImage: "live"),
            .faceMatchBelowThreshold(similarity: 0.4),
            .modelLoadFailed(detail: "x"),
            .cancelledByUser,
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test func checksumFailureNamesTheField() {
        let description = VIDError.mrzChecksumFailed(field: "expiryDate").errorDescription
        #expect(description?.contains("expiryDate") == true)
    }

    @Test func noFaceDetectedNamesTheImage() {
        #expect(VIDError.noFaceDetected(inImage: "document").errorDescription?.contains("document") == true)
    }

    @Test func multipleFacesReadsAsSingleSubjectGuidance() {
        #expect(VIDError.multipleFacesDetected(inImage: "live").errorDescription?.contains("one") == true)
    }
}
