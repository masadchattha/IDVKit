//
//  IDVErrorTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore
import Testing

struct IDVErrorTests {
    /// Every error must surface a non-empty, user-presentable description.
    @Test func everyErrorHasADescription() {
        let errors: [IDVError] = [
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
            .cancelledByUser
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test func checksumFailureNamesTheField() {
        let description = IDVError.mrzChecksumFailed(field: "expiryDate").errorDescription
        #expect(description?.contains("expiryDate") == true)
    }

    @Test func noFaceDetectedNamesTheImage() {
        #expect(IDVError.noFaceDetected(inImage: "document").errorDescription?.contains("document") == true)
    }

    @Test func multipleFacesReadsAsSingleSubjectGuidance() {
        #expect(IDVError.multipleFacesDetected(inImage: "live").errorDescription?.contains("one") == true)
    }
}
