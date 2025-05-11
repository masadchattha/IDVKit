//
//  VIDMRZParserTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Testing
import VerifIDCore
@testable import VerifIDMRZ

// ICAO 9303 part 4 Appendix B specimen (Utopia / ANNA MARIA ERIKSSON).
private let specimenLine1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
private let specimenLine2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"

@Suite struct CheckDigitTests {
    // Worked examples from ICAO Doc 9303 part 3, §4.9.
    @Test func documentNumberCheckDigit() {
        #expect(VIDMRZParser.checkDigit(for: "L898902C3") == 6)
    }

    @Test func birthDateCheckDigit() {
        #expect(VIDMRZParser.checkDigit(for: "740812") == 2)
    }

    @Test func expiryDateCheckDigit() {
        #expect(VIDMRZParser.checkDigit(for: "120415") == 9)
    }

    @Test func fillerOnlyIsZero() {
        #expect(VIDMRZParser.checkDigit(for: "<<<<<<<<<<<<<<") == 0)
    }

    @Test func invalidCharacterReturnsNil() {
        #expect(VIDMRZParser.checkDigit(for: "AB!12") == nil)
    }
}

@Suite struct TD3ParserTests {
    @Test func parsesICAOSpecimen() throws {
        let mrz = try VIDMRZParser.parseTD3(line1: specimenLine1, line2: specimenLine2)
        #expect(mrz.documentType == "P")
        #expect(mrz.issuingCountry == "UTO")
        #expect(mrz.surname == "ERIKSSON")
        #expect(mrz.givenNames == "ANNA MARIA")
        #expect(mrz.documentNumber == "L898902C3")
        #expect(mrz.nationality == "UTO")
        #expect(mrz.birthDate == "740812")
        #expect(mrz.sex == "F")
        #expect(mrz.expiryDate == "120415")
    }

    @Test func rejectsWrongLength() {
        #expect(throws: VIDError.self) {
            try VIDMRZParser.parseTD3(line1: "P<UTO", line2: specimenLine2)
        }
    }

    @Test func rejectsTamperedDocumentNumber() {
        // Flip one character of the document number; its check digit must fail.
        let tampered = "X" + specimenLine2.dropFirst()
        #expect(throws: VIDError.mrzChecksumFailed(field: "documentNumber")) {
            try VIDMRZParser.parseTD3(line1: specimenLine1, line2: tampered)
        }
    }
}

// ICAO 9303 Part 5 TD1 specimen (Utopia / ANNA MARIA ERIKSSON).
private let td1Line1 = "I<UTOD231458907<<<<<<<<<<<<<<<"
private let td1Line2 = "7408122F1204159UTO<<<<<<<<<<<6"
private let td1Line3 = "ERIKSSON<<ANNA<MARIA<<<<<<<<<<"

@Suite struct TD1ParserTests {
    @Test func parsesICAOSpecimen() throws {
        let mrz = try VIDMRZParser.parseTD1(line1: td1Line1, line2: td1Line2, line3: td1Line3)
        #expect(mrz.format == .td1)
        #expect(mrz.documentType == "I")
        #expect(mrz.issuingCountry == "UTO")
        #expect(mrz.documentNumber == "D23145890")
        #expect(mrz.nationality == "UTO")
        #expect(mrz.surname == "ERIKSSON")
        #expect(mrz.givenNames == "ANNA MARIA")
        #expect(mrz.birthDate == "740812")
        #expect(mrz.sex == "F")
        #expect(mrz.expiryDate == "120415")
    }

    @Test func rejectsWrongLength() {
        #expect(throws: VIDError.self) {
            try VIDMRZParser.parseTD1(line1: "I<UTO", line2: td1Line2, line3: td1Line3)
        }
    }

    @Test func rejectsTamperedExpiry() {
        // Break the expiry check digit; the composite check must also fail.
        let tampered = String(td1Line2.prefix(14)) + "8" + td1Line2.dropFirst(15)
        #expect(throws: VIDError.self) {
            try VIDMRZParser.parseTD1(line1: td1Line1, line2: tampered, line3: td1Line3)
        }
    }
}

// ICAO 9303 Part 6 TD2 specimen (Utopia / ANNA MARIA ERIKSSON).
private let td2Line1 = "I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<"
private let td2Line2 = "D231458907UTO7408122F1204159<<<<<<<6"

@Suite struct TD2ParserTests {
    @Test func parsesICAOSpecimen() throws {
        let mrz = try VIDMRZParser.parseTD2(line1: td2Line1, line2: td2Line2)
        #expect(mrz.format == .td2)
        #expect(mrz.documentType == "I")
        #expect(mrz.issuingCountry == "UTO")
        #expect(mrz.documentNumber == "D23145890")
        #expect(mrz.nationality == "UTO")
        #expect(mrz.surname == "ERIKSSON")
        #expect(mrz.givenNames == "ANNA MARIA")
        #expect(mrz.birthDate == "740812")
        #expect(mrz.sex == "F")
        #expect(mrz.expiryDate == "120415")
    }

    @Test func rejectsTamperedDocumentNumber() {
        // Break the printed document-number check digit (index 9).
        let tampered = String(td2Line2.prefix(9)) + "0" + td2Line2.dropFirst(10)
        #expect(throws: VIDError.mrzChecksumFailed(field: "documentNumber")) {
            try VIDMRZParser.parseTD2(line1: td2Line1, line2: tampered)
        }
    }
}

@Suite struct MRZDispatchTests {
    @Test func dispatchesByLayout() throws {
        #expect(try VIDMRZParser.parse(lines: [specimenLine1, specimenLine2]).format == .td3)
        #expect(try VIDMRZParser.parse(lines: [td2Line1, td2Line2]).format == .td2)
        #expect(try VIDMRZParser.parse(lines: [td1Line1, td1Line2, td1Line3]).format == .td1)
    }

    @Test func td1AndTd2ShareTheSameChipKey() throws {
        // The BAC/PACE key derives from doc# + DOB + expiry — identical across
        // formats for the same holder, so the chip unlocks regardless of layout.
        let td1 = try VIDMRZParser.parseTD1(line1: td1Line1, line2: td1Line2, line3: td1Line3)
        let td2 = try VIDMRZParser.parseTD2(line1: td2Line1, line2: td2Line2)
        let key1 = VIDMRZKey(documentNumber: td1.documentNumber, birthDate: td1.birthDate, expiryDate: td1.expiryDate)
        let key2 = VIDMRZKey(documentNumber: td2.documentNumber, birthDate: td2.birthDate, expiryDate: td2.expiryDate)
        #expect(try key1.seedString() == key2.seedString())
        #expect(try key1.seedString() == "D23145890774081221204159")
    }
}

@Suite struct MRZKeyTests {
    @Test func seedStringMatchesICAOKeySeedInput() throws {
        // ICAO 9303 part 11 BAC worked example uses this MRZ-information string.
        let key = VIDMRZKey(documentNumber: "L898902C3", birthDate: "740812", expiryDate: "120415")
        #expect(try key.seedString() == "L898902C3674081221204159")
    }

    @Test func shortDocumentNumberIsPaddedToNine() throws {
        let key = VIDMRZKey(documentNumber: "D2314589", birthDate: "340712", expiryDate: "950712")
        let seed = try key.seedString()
        #expect(seed.hasPrefix("D2314589<"))
        #expect(seed.count == 9 + 1 + 6 + 1 + 6 + 1)
    }
}

@Suite struct OCRNormalizationTests {
    @Test func stripsSpacesAndExpandsGuillemets() {
        // OCR often reads "<<" as "«" and injects stray spaces.
        let noisy = specimenLine1.replacingOccurrences(of: "<<ANNA", with: "«ANNA") + " "
        #expect(VIDMRZScanner.normalizeMRZLine(noisy) == specimenLine1)
    }

    @Test func rejectsWrongLengthLines() {
        #expect(VIDMRZScanner.normalizeMRZLine("HELLO") == nil)
    }

    @Test func rejectsNonMRZCharacters() {
        let line = String(repeating: "?", count: 44)
        #expect(VIDMRZScanner.normalizeMRZLine(line) == nil)
    }
}

@Suite struct OCRCorrectionTests {
    // ICAO specimen TD3 line 2 (all check digits valid).
    private let goodLine2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"

    @Test func correctsDigitFieldMisreads() {
        // OCR-B misreads in digit-only fields: date of birth 740812 → 74O8I2.
        let misread = "L898902C36UTO74O8I22F1204159ZE184226B<<<<<10"
        let corrected = VIDMRZScanner.correctTD3DataLine(misread)
        #expect(corrected == goodLine2)
    }

    @Test func leavesAlphanumericFieldsUntouched() {
        // The document number field (0–8) is alphanumeric — letters must stay.
        let corrected = VIDMRZScanner.correctTD3DataLine(goodLine2)
        #expect(corrected.prefix(9) == "L898902C3")
    }

    @Test func correctedLineParsesWhenRawWouldFail() {
        let misread = "L898902C36UTO74O8I22F1204159ZE184226B<<<<<10"
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        // Raw misread fails the birth-date check digit; corrected line parses.
        #expect(throws: VIDError.self) {
            try VIDMRZParser.parseTD3(line1: line1, line2: misread)
        }
        let corrected = VIDMRZScanner.correctTD3DataLine(misread)
        #expect(throws: Never.self) {
            try VIDMRZParser.parseTD3(line1: line1, line2: corrected)
        }
    }
}
