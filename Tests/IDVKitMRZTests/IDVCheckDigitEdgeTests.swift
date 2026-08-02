//
//  IDVCheckDigitEdgeTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import IDVKitMRZ
import Testing

struct IDVCheckDigitEdgeTests {
    @Test func fillerOnlyAndEmptyAreZero() {
        #expect(IDVMRZParser.checkDigit(for: "<<<<<<") == 0)
        #expect(IDVMRZParser.checkDigit(for: "") == 0)
    }

    @Test func lowercaseIsUppercasedBeforeWeighting() {
        #expect(IDVMRZParser.checkDigit(for: "l898902c3") == IDVMRZParser.checkDigit(for: "L898902C3"))
    }

    @Test func charactersOutsideTheMRZSetReturnNil() {
        #expect(IDVMRZParser.checkDigit(for: "AB!12") == nil)
        #expect(IDVMRZParser.checkDigit(for: "ÄÖÜ") == nil)
    }

    @Test func validationMatchesComputation() {
        #expect(IDVMRZParser.isCheckDigitValid(value: "L898902C3", digit: "6"))
        #expect(!IDVMRZParser.isCheckDigitValid(value: "L898902C3", digit: "7"))
    }
}
