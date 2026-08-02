//
//  IDVMRZDateTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import Testing
@testable import IDVKitCore

struct MRZDateInterpreterTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func components(_ date: Date) -> (year: Int, month: Int, day: Int) {
        (utc.component(.year, from: date), utc.component(.month, from: date), utc.component(.day, from: date))
    }

    /// "now" fixed at 2026 so the century inference is deterministic.
    private let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 1, day: 1).date!

    @Test func birthDateInPastCentury() throws {
        let date = try #require(IDVMRZDateInterpreter.date(fromYYMMDD: "920625", kind: .birth, now: now))
        let c = components(date)
        #expect(c.year == 1992)
        #expect(c.month == 6)
        #expect(c.day == 25)
    }

    @Test func birthYearAfterNowIsPreviousCentury() throws {
        // "27" would be 2027 (future) → interpreted as 1927.
        let date = try #require(IDVMRZDateInterpreter.date(fromYYMMDD: "270101", kind: .birth, now: now))
        #expect(components(date).year == 1927)
    }

    @Test func expiryPivotsAt70() throws {
        let future = try #require(IDVMRZDateInterpreter.date(fromYYMMDD: "300318", kind: .expiry, now: now))
        #expect(components(future).year == 2030)
        let past = try #require(IDVMRZDateInterpreter.date(fromYYMMDD: "990101", kind: .expiry, now: now))
        #expect(components(past).year == 1999)
    }

    @Test func rejectsMalformedDates() {
        #expect(IDVMRZDateInterpreter.date(fromYYMMDD: "991350", kind: .birth) == nil) // month 13
        #expect(IDVMRZDateInterpreter.date(fromYYMMDD: "12345", kind: .birth) == nil) // too short
        #expect(IDVMRZDateInterpreter.date(fromYYMMDD: "AB0101", kind: .birth) == nil) // non-numeric
    }

    @Test func mrzDataExposesFormattedDates() {
        let mrz = IDVMRZData(
            format: .td3, documentType: "P", issuingCountry: "PAK",
            documentNumber: "AE9160071", nationality: "PAK", surname: "REHMAT",
            givenNames: "SHEHZAD", birthDate: "920625", expiryDate: "300318", sex: "M"
        )
        #expect(mrz.dateOfBirth != nil)
        #expect(mrz.formattedDateOfBirth?.isEmpty == false)
        #expect(mrz.sexDescription == "Male")
    }
}
