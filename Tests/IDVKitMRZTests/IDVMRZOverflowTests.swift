//
//  IDVMRZOverflowTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Testing
@testable import IDVKitMRZ

struct IDVMRZOverflowTests {
    @Test func shortNumberIsReturnedWithItsPrintedCheck() {
        let (number, check) = IDVMRZParser.reconstructDocumentNumber(
            field: "AB1234567", checkChar: "5", optionalData: "<<<<<<"
        )
        #expect(number == "AB1234567")
        #expect(check == "5")
    }

    @Test func overflowNumberContinuesIntoOptionalData() {
        // Check position is '<' → the number spills into optional data, terminated
        // by the real check digit and '<' fillers.
        let (number, check) = IDVMRZParser.reconstructDocumentNumber(
            field: "AB1234567", checkChar: "<", optionalData: "8901<<<"
        )
        #expect(number == "AB1234567890")
        #expect(check == "1")
    }

    @Test func paddedShortNumberKeepsItsFillers() {
        // A number shorter than 9 keeps its '<' padding for check-digit purposes.
        let (number, check) = IDVMRZParser.reconstructDocumentNumber(
            field: "L898902C3", checkChar: "6", optionalData: ""
        )
        #expect(number == "L898902C3")
        #expect(check == "6")
    }
}
