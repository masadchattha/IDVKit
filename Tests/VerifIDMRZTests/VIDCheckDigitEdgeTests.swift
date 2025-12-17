//
//  VIDCheckDigitEdgeTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Testing
import VerifIDMRZ

struct VIDCheckDigitEdgeTests {
    @Test func fillerOnlyAndEmptyAreZero() {
        #expect(VIDMRZParser.checkDigit(for: "<<<<<<") == 0)
        #expect(VIDMRZParser.checkDigit(for: "") == 0)
    }

    @Test func lowercaseIsUppercasedBeforeWeighting() {
        #expect(VIDMRZParser.checkDigit(for: "l898902c3") == VIDMRZParser.checkDigit(for: "L898902C3"))
    }

    @Test func charactersOutsideTheMRZSetReturnNil() {
        #expect(VIDMRZParser.checkDigit(for: "AB!12") == nil)
        #expect(VIDMRZParser.checkDigit(for: "ÄÖÜ") == nil)
    }

    @Test func validationMatchesComputation() {
        #expect(VIDMRZParser.isCheckDigitValid(value: "L898902C3", digit: "6"))
        #expect(!VIDMRZParser.isCheckDigitValid(value: "L898902C3", digit: "7"))
    }
}
