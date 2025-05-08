//
//  VIDMRZParser.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation
import VerifIDCore

/// ICAO Doc 9303 MRZ parsing with full check-digit validation.
/// Own implementation — no third-party OCR or parser dependencies.
public enum VIDMRZParser {
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
    /// - Throws: ``VIDError/mrzInvalidFormat(detail:)`` or
    ///   ``VIDError/mrzChecksumFailed(field:)``.
    public static func parseTD3(line1: String, line2: String) throws -> VIDMRZData {
        guard line1.count == 44, line2.count == 44 else {
            throw VIDError.mrzInvalidFormat(detail: "TD3 requires two 44-character lines")
        }
        let l1 = Array(line1.uppercased())
        let l2 = Array(line2.uppercased())

        func slice(_ chars: [Character], _ range: Range<Int>) -> String {
            String(chars[range])
        }

        let documentNumber = slice(l2, 0 ..< 9)
        let birthDate = slice(l2, 13 ..< 19)
        let expiryDate = slice(l2, 21 ..< 27)

        guard isCheckDigitValid(value: documentNumber, digit: l2[9]) else {
            throw VIDError.mrzChecksumFailed(field: "documentNumber")
        }
        guard isCheckDigitValid(value: birthDate, digit: l2[19]) else {
            throw VIDError.mrzChecksumFailed(field: "birthDate")
        }
        guard isCheckDigitValid(value: expiryDate, digit: l2[27]) else {
            throw VIDError.mrzChecksumFailed(field: "expiryDate")
        }
        let composite = slice(l2, 0 ..< 10) + slice(l2, 13 ..< 20) + slice(l2, 21 ..< 43)
        guard isCheckDigitValid(value: composite, digit: l2[43]) else {
            throw VIDError.mrzChecksumFailed(field: "composite")
        }

        let names = slice(l1, 5 ..< 44)
        let nameParts = names.components(separatedBy: "<<")
        let surname = nameParts[0].replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let givenNames = nameParts.count > 1
            ? nameParts[1].replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespaces)
            : ""

        return VIDMRZData(
            format: .td3,
            documentType: slice(l1, 0 ..< 2).replacingOccurrences(of: "<", with: ""),
            issuingCountry: slice(l1, 2 ..< 5).replacingOccurrences(of: "<", with: ""),
            documentNumber: documentNumber.replacingOccurrences(of: "<", with: ""),
            nationality: slice(l2, 10 ..< 13).replacingOccurrences(of: "<", with: ""),
            surname: surname,
            givenNames: givenNames,
            birthDate: birthDate,
            expiryDate: expiryDate,
            sex: String(l2[20]).replacingOccurrences(of: "<", with: ""),
            optionalData: slice(l2, 28 ..< 42).replacingOccurrences(of: "<", with: "")
        )
    }

    /// Parses a TD1 (ID card / residence permit) MRZ — three lines of 30
    /// characters. Validates the document-number, birth-date, expiry-date and
    /// composite check digits, and reconstructs document numbers that overflow
    /// into the optional-data field (ICAO 9303 Part 5).
    public static func parseTD1(line1: String, line2: String, line3: String) throws -> VIDMRZData {
        guard line1.count == 30, line2.count == 30, line3.count == 30 else {
            throw VIDError.mrzInvalidFormat(detail: "TD1 requires three 30-character lines")
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
            throw VIDError.mrzChecksumFailed(field: "documentNumber")
        }

        // Line 2: DOB[0..6], DOB check[6], sex[7], expiry[8..14], expiry check[14],
        // nationality[15..18], optional data 2[18..29], composite check[29].
        let birthDate = slice(l2, 0 ..< 6)
        let expiryDate = slice(l2, 8 ..< 14)
        guard isCheckDigitValid(value: birthDate, digit: l2[6]) else {
            throw VIDError.mrzChecksumFailed(field: "birthDate")
        }
        guard isCheckDigitValid(value: expiryDate, digit: l2[14]) else {
            throw VIDError.mrzChecksumFailed(field: "expiryDate")
        }
        // Composite: line1[5..30] + line2[0..7] + line2[8..15] + line2[18..29].
        let composite = slice(l1, 5 ..< 30) + slice(l2, 0 ..< 7) + slice(l2, 8 ..< 15) + slice(l2, 18 ..< 29)
        guard isCheckDigitValid(value: composite, digit: l2[29]) else {
            throw VIDError.mrzChecksumFailed(field: "composite")
        }

        let (surname, givenNames) = parseName(slice(l3, 0 ..< 30))
        return VIDMRZData(
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
            optionalData: slice(l1, 15 ..< 30).replacingOccurrences(of: "<", with: "")
        )
    }

    /// Parses a TD2 (older ID document / visa) MRZ — two lines of 36 characters
    /// (ICAO 9303 Part 6). Validates all four check digits and reconstructs an
    /// overflowing document number.
    public static func parseTD2(line1: String, line2: String) throws -> VIDMRZData {
        guard line1.count == 36, line2.count == 36 else {
            throw VIDError.mrzInvalidFormat(detail: "TD2 requires two 36-character lines")
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
            throw VIDError.mrzChecksumFailed(field: "documentNumber")
        }
        let birthDate = slice(l2, 13 ..< 19)
        let expiryDate = slice(l2, 21 ..< 27)
        guard isCheckDigitValid(value: birthDate, digit: l2[19]) else {
            throw VIDError.mrzChecksumFailed(field: "birthDate")
        }
        guard isCheckDigitValid(value: expiryDate, digit: l2[27]) else {
            throw VIDError.mrzChecksumFailed(field: "expiryDate")
        }
        // Composite: line2[0..10] + line2[13..20] + line2[21..28] + line2[28..35].
        let composite = slice(l2, 0 ..< 10) + slice(l2, 13 ..< 20) + slice(l2, 21 ..< 28) + slice(l2, 28 ..< 35)
        guard isCheckDigitValid(value: composite, digit: l2[35]) else {
            throw VIDError.mrzChecksumFailed(field: "composite")
        }

        let (surname, givenNames) = parseName(slice(l1, 5 ..< 36))
        return VIDMRZData(
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
            optionalData: slice(l2, 28 ..< 35).replacingOccurrences(of: "<", with: "")
        )
    }

    /// Dispatches to the right parser based on line count and width:
    /// 3×30 → TD1, 2×36 → TD2, 2×44 → TD3.
    public static func parse(lines: [String]) throws -> VIDMRZData {
        switch lines.count {
        case 3 where lines.allSatisfy { $0.count == 30 }:
            return try parseTD1(line1: lines[0], line2: lines[1], line3: lines[2])
        case 2 where lines[0].count == 36:
            return try parseTD2(line1: lines[0], line2: lines[1])
        case 2 where lines[0].count == 44:
            return try parseTD3(line1: lines[0], line2: lines[1])
        default:
            throw VIDError.mrzInvalidFormat(detail: "unrecognized MRZ layout (\(lines.count) lines)")
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
public struct VIDMRZKey: Sendable, Equatable {
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
    /// - Throws: ``VIDError/mrzInvalidFormat(detail:)`` if any field contains
    ///   characters outside the MRZ character set.
    public func seedString() throws -> String {
        let padded = documentNumber.uppercased()
            .padding(toLength: max(9, documentNumber.count), withPad: "<", startingAt: 0)
        guard
            let cd1 = VIDMRZParser.checkDigit(for: padded),
            let cd2 = VIDMRZParser.checkDigit(for: birthDate),
            let cd3 = VIDMRZParser.checkDigit(for: expiryDate)
        else {
            throw VIDError.mrzInvalidFormat(detail: "MRZ key fields contain invalid characters")
        }
        return "\(padded)\(cd1)\(birthDate)\(cd2)\(expiryDate)\(cd3)"
    }
}
