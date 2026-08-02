//
//  IDVMRZClassificationTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import IDVKitCore
import Testing

struct IDVMRZClassificationTests {
    private func mrz(_ format: IDVMRZData.Format, _ code: String) -> IDVMRZData {
        IDVMRZData(
            format: format, documentType: code, issuingCountry: "UTO",
            documentNumber: "L898902C3", nationality: "UTO", surname: "ERIKSSON",
            givenNames: "ANNA MARIA", birthDate: "740812", expiryDate: "120415", sex: "F"
        )
    }

    @Test func td3PassportIsDetectedAsPassport() {
        let p = mrz(.td3, "P")
        #expect(p.detectedDocumentKind == .passport)
        #expect(p.matches(.passport))
        #expect(!p.matches(.idCard))
        #expect(!p.matches(.residencePermit))
    }

    @Test func td1CardIsDetectedAsCard() {
        let c = mrz(.td1, "I")
        #expect(c.detectedDocumentKind == .idCard)
        #expect(c.matches(.idCard))
        // The MRZ can't separate an ID card from a residence permit, so both match.
        #expect(c.matches(.residencePermit))
        #expect(!c.matches(.passport))
    }

    @Test func passportCardOnTD1IsStillAPassport() {
        // `IP` is a passport card carried on the TD1 layout.
        let ip = mrz(.td1, "IP")
        #expect(ip.detectedDocumentKind == .passport)
        #expect(ip.matches(.passport))
    }

    @Test func td3AlwaysBeatsAnOddCode() {
        // A TD3 layout is a passport booklet regardless of an OCR-garbled code.
        #expect(mrz(.td3, "X").detectedDocumentKind == .passport)
    }

    @Test func anyMatchesEverything() {
        #expect(mrz(.td1, "I").matches(.any))
        #expect(mrz(.td3, "P").matches(.any))
    }
}
