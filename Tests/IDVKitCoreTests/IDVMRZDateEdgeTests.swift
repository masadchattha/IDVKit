//
//  IDVMRZDateEdgeTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import Testing
import IDVKitCore

struct IDVMRZDateEdgeTests {
    private let cal = Calendar(identifier: .gregorian)
    private var now: Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
    }

    private func year(of value: String, kind: IDVMRZDateInterpreter.Kind) -> Int? {
        IDVMRZDateInterpreter.date(fromYYMMDD: value, kind: kind, now: now)
            .map { cal.component(.year, from: $0) }
    }

    @Test func birthYearNeverLandsInTheFuture() {
        // A birth year after the current two-digit year belongs to the 1900s.
        #expect(year(of: "990615", kind: .birth) == 1999)
        #expect(year(of: "200615", kind: .birth) == 2020)
    }

    @Test func expiryUsesTheSeventyPivot() {
        #expect(year(of: "300615", kind: .expiry) == 2030)
        #expect(year(of: "850615", kind: .expiry) == 1985)
    }

    @Test func invalidInputReturnsNil() {
        #expect(IDVMRZDateInterpreter.date(fromYYMMDD: "abcdef", kind: .birth, now: now) == nil)
        #expect(IDVMRZDateInterpreter.date(fromYYMMDD: "9913", kind: .expiry, now: now) == nil)
    }
}
