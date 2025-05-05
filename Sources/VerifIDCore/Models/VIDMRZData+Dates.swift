//
//  VIDMRZData+Dates.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation

extension VIDMRZData {

    /// The holder's date of birth as a `Date`, or `nil` if the MRZ field is
    /// malformed. MRZ dates carry only a two-digit year; the century is inferred.
    public var dateOfBirth: Date? {
        VIDMRZDateInterpreter.date(fromYYMMDD: birthDate, kind: .birth)
    }

    /// The document's expiry date as a `Date`, or `nil` if malformed.
    public var dateOfExpiry: Date? {
        VIDMRZDateInterpreter.date(fromYYMMDD: expiryDate, kind: .expiry)
    }

    /// Date of birth formatted for display (locale-aware, e.g. "25 Jun 1992").
    public var formattedDateOfBirth: String? {
        dateOfBirth.map(VIDMRZDateInterpreter.displayString)
    }

    /// Expiry date formatted for display (locale-aware, e.g. "18 Mar 2030").
    public var formattedDateOfExpiry: String? {
        dateOfExpiry.map(VIDMRZDateInterpreter.displayString)
    }

    /// `true` when the document's expiry date is in the past.
    public var isExpired: Bool {
        guard let expiry = dateOfExpiry else { return false }
        return expiry < Date()
    }

    /// A human-readable sex, or `nil` when unspecified (`<`).
    public var sexDescription: String? {
        switch sex.uppercased() {
        case "M": "Male"
        case "F": "Female"
        default: nil
        }
    }
}

/// Interprets ICAO 9303 `YYMMDD` MRZ dates, which omit the century.
public enum VIDMRZDateInterpreter {

    public enum Kind {
        /// Always in the past — a two-digit year after the current year is
        /// treated as the previous century.
        case birth
        /// Near the present — pivoted at 70 (`00`–`69` → 2000s, `70`–`99` → 1900s).
        case expiry
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    /// Parses a `YYMMDD` string into a `Date`, inferring the century by `kind`.
    public static func date(fromYYMMDD value: String, kind: Kind, now: Date = Date()) -> Date? {
        guard value.count == 6, value.allSatisfy(\.isNumber) else { return nil }
        let yy = Int(value.prefix(2))!
        let mm = Int(value.dropFirst(2).prefix(2))!
        let dd = Int(value.suffix(2))!
        guard (1...12).contains(mm), (1...31).contains(dd) else { return nil }

        let currentYY = utcCalendar.component(.year, from: now) % 100
        let year: Int
        switch kind {
        case .birth: year = yy <= currentYY ? 2000 + yy : 1900 + yy
        case .expiry: year = yy < 70 ? 2000 + yy : 1900 + yy
        }

        var components = DateComponents()
        components.year = year
        components.month = mm
        components.day = dd
        return utcCalendar.date(from: components)
    }

    /// Formats a date as a locale-aware medium display string (e.g. "25 Jun 1992").
    public static func displayString(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
