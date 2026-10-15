//
//  IDVMRZParser.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore

/// ICAO Doc 9303 MRZ parsing with full check-digit validation.
/// Own implementation — no third-party OCR or parser dependencies.
public enum IDVMRZParser {
    /// Computes the ICAO 9303 part 3 check digit for a value:
    /// weights 7-3-1 repeating, `A`–`Z` map to 10–35, `<` maps to 0.
    /// - Returns: `nil` if the value contains characters outside the MRZ set.
    public static func checkDigit(for value: String) -> Int? {
        let weights = [7, 3, 1]
        var sum = 0
        for (index, char) in value.uppercased().enumerated() {
            let v: Int
            switch char {
            case "0" ... "9": v = Int(String(char))!
            case "A" ... "Z": v = Int(char.asciiValue! - Character("A").asciiValue!) + 10
            case "<": v = 0
            default: return nil
            }
            sum += v * weights[index % 3]
        }
        return sum % 10
    }

    /// Validates a value against its printed check digit.
    public static func isCheckDigitValid(value: String, digit: Character) -> Bool {
        guard let expected = checkDigit(for: value), let actual = digit.wholeNumberValue else {
            return false
        }
        return expected == actual
    }

    /// Parses a TD3 (passport) MRZ — two lines of 44 characters.
    ///
    /// All four mandatory check digits (document number, birth date, expiry
    /// date, composite) are verified; a single OCR error is rejected here
    /// rather than surfacing later as an NFC access failure.
    ///
    /// - Throws: ``IDVError/mrzInvalidFormat(detail:)`` or
    ///   ``IDVError/mrzChecksumFailed(field:)``.
    public static func parseTD3(line1: String, line2: String) throws -> IDVMRZData {
        let (data, failures) = try parseTD3Tolerant(line1: line1, line2: line2)
        if let field = failures.first {
            throw IDVError.mrzChecksumFailed(field: field)
        }
        return data
    }

    /// Parses TD3 without failing on a bad check digit — used for chip DG1, where
    /// passive authentication already proves integrity and some genuine passports
    /// carry a known DG1 check-digit error.
    ///
    /// - Returns: the parsed data and the names of any fields whose check digit
    ///   did not verify (empty when all four pass). A structural problem (wrong
    ///   line length) still throws.
    package static func parseTD3Tolerant(line1: String, line2: String) throws -> (data: IDVMRZData, checksumFailures: [String]) {
        guard line1.count == 44, line2.count == 44 else {
            throw IDVError.mrzInvalidFormat(detail: "TD3 requires two 44-character lines")
        }
        let l1 = Array(line1.uppercased())
        let l2 = Array(line2.uppercased())
        return (makeTD3(l1, l2, rawLines: [String(l1), String(l2)]), td3ChecksumFailures(l2))
    }

    /// The TD3 fields whose printed check digit does not verify, in MRZ order.
    private static func td3ChecksumFailures(_ l2: [Character]) -> [String] {
        func slice(_ r: Range<Int>) -> String {
            String(l2[r])
        }
        var failures: [String] = []
        if !isCheckDigitValid(value: slice(0 ..< 9), digit: l2[9]) {
            failures.append("documentNumber")
        }
        if !isCheckDigitValid(value: slice(13 ..< 19), digit: l2[19]) {
            failures.append("birthDate")
        }
        if !isCheckDigitValid(value: slice(21 ..< 27), digit: l2[27]) {
            failures.append("expiryDate")
        }
        let composite = slice(0 ..< 10) + slice(13 ..< 20) + slice(21 ..< 43)
        if !isCheckDigitValid(value: composite, digit: l2[43]) {
            failures.append("composite")
        }
        return failures
    }

    /// Builds `IDVMRZData` from validated TD3 lines (no check-digit validation).
    private static func makeTD3(_ l1: [Character], _ l2: [Character], rawLines: [String]) -> IDVMRZData {
        func slice(_ chars: [Character], _ range: Range<Int>) -> String {
            String(chars[range])
        }

        let names = slice(l1, 5 ..< 44)
        let nameParts = names.components(separatedBy: "<<")
        let surname = nameParts[0].replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let givenNames = nameParts.count > 1
            ? nameParts[1].replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespaces)
            : ""

        return IDVMRZData(
            format: .td3,
            documentType: slice(l1, 0 ..< 2).replacingOccurrences(of: "<", with: ""),
            issuingCountry: slice(l1, 2 ..< 5).replacingOccurrences(of: "<", with: ""),
            documentNumber: slice(l2, 0 ..< 9).replacingOccurrences(of: "<", with: ""),
            nationality: slice(l2, 10 ..< 13).replacingOccurrences(of: "<", with: ""),
            surname: surname,
            givenNames: givenNames,
            birthDate: slice(l2, 13 ..< 19),
            expiryDate: slice(l2, 21 ..< 27),
            sex: String(l2[20]).replacingOccurrences(of: "<", with: ""),
            optionalData: slice(l2, 28 ..< 42).replacingOccurrences(of: "<", with: ""),
            rawLines: rawLines
        )
    }

    /// Parses a TD1 (ID card / residence permit) MRZ — three lines of 30
    /// characters. Validates the document-number, birth-date, expiry-date and
    /// composite check digits, and reconstructs document numbers that overflow
    /// into the optional-data field (ICAO 9303 Part 5).
    public static func parseTD1(line1: String, line2: String, line3: String) throws -> IDVMRZData {
        guard line1.count == 30, line2.count == 30, line3.count == 30 else {
            throw IDVError.mrzInvalidFormat(detail: "TD1 requires three 30-character lines")
        }
        let l1 = Array(line1.uppercased())
        let l2 = Array(line2.uppercased())
        let l3 = Array(line3.uppercased())
        func slice(_ chars: [Character], _ range: Range<Int>) -> String {
            String(chars[range])
        }

        // Line 1: doc code[0..2], issuing state[2..5], doc number[5..14],
        // doc-number check[14], optional data 1[15..30].
        let (documentNumber, docCheck) = reconstructDocumentNumber(
            field: slice(l1, 5 ..< 14), checkChar: l1[14], optionalData: slice(l1, 15 ..< 30)
        )
        guard isCheckDigitValid(value: documentNumber, digit: docCheck) else {
            throw IDVError.mrzChecksumFailed(field: "documentNumber")
        }

        // Line 2: DOB[0..6], DOB check[6], sex[7], expiry[8..14], expiry check[14],
        // nationality[15..18], optional data 2[18..29], composite check[29].
        let birthDate = slice(l2, 0 ..< 6)
        let expiryDate = slice(l2, 8 ..< 14)
        guard isCheckDigitValid(value: birthDate, digit: l2[6]) else {
            throw IDVError.mrzChecksumFailed(field: "birthDate")
        }
        guard isCheckDigitValid(value: expiryDate, digit: l2[14]) else {
            throw IDVError.mrzChecksumFailed(field: "expiryDate")
        }
        // Composite: line1[5..30] + line2[0..7] + line2[8..15] + line2[18..29].
        let composite = slice(l1, 5 ..< 30) + slice(l2, 0 ..< 7) + slice(l2, 8 ..< 15) + slice(l2, 18 ..< 29)
        guard isCheckDigitValid(value: composite, digit: l2[29]) else {
            throw IDVError.mrzChecksumFailed(field: "composite")
        }

        let (surname, givenNames) = parseName(slice(l3, 0 ..< 30))
        return IDVMRZData(
            format: .td1,
            documentType: slice(l1, 0 ..< 2).replacingOccurrences(of: "<", with: ""),
            issuingCountry: slice(l1, 2 ..< 5).replacingOccurrences(of: "<", with: ""),
            documentNumber: documentNumber.replacingOccurrences(of: "<", with: ""),
            nationality: slice(l2, 15 ..< 18).replacingOccurrences(of: "<", with: ""),
            surname: surname,
            givenNames: givenNames,
            birthDate: birthDate,
            expiryDate: expiryDate,
            sex: String(l2[7]).replacingOccurrences(of: "<", with: ""),
            optionalData: slice(l1, 15 ..< 30).replacingOccurrences(of: "<", with: ""),
            rawLines: [String(l1), String(l2), String(l3)]
        )
    }

    /// Parses a TD2 (older ID document / visa) MRZ — two lines of 36 characters
    /// (ICAO 9303 Part 6). Validates all four check digits and reconstructs an
    /// overflowing document number.
    public static func parseTD2(line1: String, line2: String) throws -> IDVMRZData {
        guard line1.count == 36, line2.count == 36 else {
            throw IDVError.mrzInvalidFormat(detail: "TD2 requires two 36-character lines")
        }
        let l1 = Array(line1.uppercased())
        let l2 = Array(line2.uppercased())
        func slice(_ chars: [Character], _ range: Range<Int>) -> String {
            String(chars[range])
        }

        // Line 2: doc number[0..9], doc check[9], nationality[10..13], DOB[13..19],
        // DOB check[19], sex[20], expiry[21..27], expiry check[27],
        // optional data[28..35], composite check[35].
        let (documentNumber, docCheck) = reconstructDocumentNumber(
            field: slice(l2, 0 ..< 9), checkChar: l2[9], optionalData: slice(l2, 28 ..< 35)
        )
        guard isCheckDigitValid(value: documentNumber, digit: docCheck) else {
            throw IDVError.mrzChecksumFailed(field: "documentNumber")
        }
        let birthDate = slice(l2, 13 ..< 19)
        let expiryDate = slice(l2, 21 ..< 27)
        guard isCheckDigitValid(value: birthDate, digit: l2[19]) else {
            throw IDVError.mrzChecksumFailed(field: "birthDate")
        }
        guard isCheckDigitValid(value: expiryDate, digit: l2[27]) else {
            throw IDVError.mrzChecksumFailed(field: "expiryDate")
        }
        // Composite: line2[0..10] + line2[13..20] + line2[21..28] + line2[28..35].
        let composite = slice(l2, 0 ..< 10) + slice(l2, 13 ..< 20) + slice(l2, 21 ..< 28) + slice(l2, 28 ..< 35)
        guard isCheckDigitValid(value: composite, digit: l2[35]) else {
            throw IDVError.mrzChecksumFailed(field: "composite")
        }

        let (surname, givenNames) = parseName(slice(l1, 5 ..< 36))
        return IDVMRZData(
            format: .td2,
            documentType: slice(l1, 0 ..< 2).replacingOccurrences(of: "<", with: ""),
            issuingCountry: slice(l1, 2 ..< 5).replacingOccurrences(of: "<", with: ""),
            documentNumber: documentNumber.replacingOccurrences(of: "<", with: ""),
            nationality: slice(l2, 10 ..< 13).replacingOccurrences(of: "<", with: ""),
            surname: surname,
            givenNames: givenNames,
            birthDate: birthDate,
            expiryDate: expiryDate,
            sex: String(l2[20]).replacingOccurrences(of: "<", with: ""),
            optionalData: slice(l2, 28 ..< 35).replacingOccurrences(of: "<", with: ""),
            rawLines: [String(l1), String(l2)]
        )
    }

    /// Dispatches to the right parser based on line count and width:
    /// 3×30 → TD1, 2×36 → TD2, 2×44 → TD3.
    public static func parse(lines: [String]) throws -> IDVMRZData {
        switch lines.count {
        case 3 where lines.allSatisfy { $0.count == 30 }:
            return try parseTD1(line1: lines[0], line2: lines[1], line3: lines[2])
        case 2 where lines[0].count == 36:
            return try parseTD2(line1: lines[0], line2: lines[1])
        case 2 where lines[0].count == 44:
            return try parseTD3(line1: lines[0], line2: lines[1])
        default:
            throw IDVError.mrzInvalidFormat(detail: "unrecognized MRZ layout (\(lines.count) lines)")
        }
    }

    // MARK: Helpers

    /// Splits an MRZ name field (`SURNAME<<GIVEN<NAMES`) into its two parts,
    /// converting fillers to spaces.
    private static func parseName(_ raw: String) -> (surname: String, givenNames: String) {
        let parts = raw.components(separatedBy: "<<")
        let surname = parts[0].replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces)
        let givenNames = parts.count > 1
            ? parts[1].replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces)
            : ""
        return (surname, givenNames)
    }

    /// Reconstructs a document number and its check digit, honoring the ICAO 9303
    /// overflow convention: when a number exceeds the 9-character field, the check
    /// position holds `<` and the remainder continues in the optional-data field,
    /// terminated by the real check digit and `<` fillers. Returns the number
    /// exactly as the check digit is computed over it (padding fillers kept for the
    /// short case, so `isCheckDigitValid` matches the printed digit).
    static func reconstructDocumentNumber(
        field: String, checkChar: Character, optionalData: String
    ) -> (number: String, check: Character) {
        guard checkChar == "<" else { return (field, checkChar) }
        // Overflow: the 9-char field is all number; the optional field holds the
        // remaining digits, then the check digit, then `<` fillers.
        let trimmed = String(optionalData.reversed().drop(while: { $0 == "<" }).reversed())
        guard let check = trimmed.last else { return (field, checkChar) }
        return (field + trimmed.dropLast(), check)
    }
}

/// The three MRZ fields that derive the chip-access (BAC/PACE) key.
/// Built from a camera scan or manual entry — this is all NFC access needs.
public struct IDVMRZKey: Sendable, Equatable {
    /// The document number, exactly as printed in the MRZ (including any trailing
    /// `<` filler — it participates in the check digit).
    public var documentNumber: String
    /// Date of birth, `YYMMDD`, as printed in the MRZ.
    public var birthDate: String
    /// Date of expiry, `YYMMDD`, as printed in the MRZ.
    public var expiryDate: String

    /// Creates a chip-access key from the three MRZ fields.
    /// - Parameters:
    ///   - documentNumber: The document number as printed in the MRZ.
    ///   - birthDate: Date of birth, `YYMMDD`.
    ///   - expiryDate: Date of expiry, `YYMMDD`.
    public init(documentNumber: String, birthDate: String, expiryDate: String) {
        self.documentNumber = documentNumber
        self.birthDate = birthDate
        self.expiryDate = expiryDate
    }

    /// The key-seed input string per ICAO 9303 part 11:
    /// document number (padded to 9 with `<`) + check digit + birth date +
    /// check digit + expiry date + check digit.
    ///
    /// - Throws: ``IDVError/mrzInvalidFormat(detail:)`` if any field contains
    ///   characters outside the MRZ character set.
    public func seedString() throws -> String {
        let padded = documentNumber.uppercased()
            .padding(toLength: max(9, documentNumber.count), withPad: "<", startingAt: 0)
        guard
            let cd1 = IDVMRZParser.checkDigit(for: padded),
            let cd2 = IDVMRZParser.checkDigit(for: birthDate),
            let cd3 = IDVMRZParser.checkDigit(for: expiryDate)
        else {
            throw IDVError.mrzInvalidFormat(detail: "MRZ key fields contain invalid characters")
        }
        return "\(padded)\(cd1)\(birthDate)\(cd2)\(expiryDate)\(cd3)"
    }
}
