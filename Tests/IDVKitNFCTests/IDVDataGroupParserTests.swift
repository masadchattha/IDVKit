//
//  IDVDataGroupParserTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import IDVKitCore
@testable import IDVKitNFC
import Testing

struct DataGroupParserTests {
    @Test func parsesDG1TD3MRZ() throws {
        // DG1 = 61 L { 5F1F L <88-char TD3 MRZ> }.
        let mrz = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<" +
            "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        let mrzBytes = Array(mrz.utf8)
        let inner: [UInt8] = [0x5F, 0x1F, 0x81, UInt8(mrzBytes.count)] + mrzBytes
        let dg1: [UInt8] = [0x61, 0x81, UInt8(inner.count)] + inner

        let (parsed, checksumFailures) = try IDVDataGroupParser.parseDG1(dg1)
        #expect(parsed.surname == "ERIKSSON")
        #expect(parsed.documentNumber == "L898902C3")
        #expect(parsed.birthDate == "740812")
        #expect(checksumFailures.isEmpty)
        #expect(parsed.rawLines == [
            "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
            "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        ])
    }

    @Test func tolerantDG1AcceptsBadCheckDigitAndRecordsIt() throws {
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        // Document-number check digit tampered 6 → 5 (as a genuine passport with a
        // known DG1 error would read).
        let badLine2 = "L898902C35UTO7408122F1204159ZE184226B<<<<<10"
        let dg1 = Self.dg1Bytes(line1 + badLine2)

        // Strict (default): a bad check digit fails the read.
        #expect(throws: IDVError.self) {
            _ = try IDVDataGroupParser.parseDG1(dg1, strictChecksums: true)
        }

        // Lenient: the data comes back and the failing field is recorded so the
        // caller can surface it as a warning (passive auth still proves integrity).
        let (parsed, failures) = try IDVDataGroupParser.parseDG1(dg1, strictChecksums: false)
        #expect(parsed.surname == "ERIKSSON")
        #expect(failures.contains("documentNumber"))
        #expect(parsed.rawLines == [line1, badLine2])
    }

    /// Wraps an 88-char TD3 MRZ string in the DG1 TLV envelope (61 → 5F1F).
    static func dg1Bytes(_ mrz: String) -> [UInt8] {
        let mrzBytes = Array(mrz.utf8)
        let inner: [UInt8] = [0x5F, 0x1F, 0x81, UInt8(mrzBytes.count)] + mrzBytes
        return [0x61, 0x81, UInt8(inner.count)] + inner
    }

    @Test func locatesJPEGInFaceRecord() throws {
        // ISO 19794-5 header bytes followed by a JPEG SOI marker.
        let header: [UInt8] = Array(repeating: 0x00, count: 46)
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]
        let (image, isJP2) = try IDVDataGroupParser.locateImage(in: header + jpeg)
        #expect(isJP2 == false)
        #expect(Array(image.prefix(3)) == [0xFF, 0xD8, 0xFF])
    }

    @Test func locatesJPEG2000CodestreamInFaceRecord() throws {
        let header: [UInt8] = Array(repeating: 0x00, count: 46)
        let j2k: [UInt8] = [0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x2F]
        let (image, isJP2) = try IDVDataGroupParser.locateImage(in: header + j2k)
        #expect(isJP2 == true)
        #expect(Array(image.prefix(2)) == [0xFF, 0x4F])
    }

    @Test func throwsWhenNoImagePresent() {
        let block: [UInt8] = Array(repeating: 0x11, count: 60)
        #expect(throws: IDVError.self) {
            _ = try IDVDataGroupParser.locateImage(in: block)
        }
    }

    @Test func parsesCOMTagList() throws {
        // 60 L { 5F01 L "0107"  5F36 L "040000"  5C L <tag list 61 75 6E> }.
        let tagList: [UInt8] = [0x5C, 0x03, 0x61, 0x75, 0x6E]
        let com: [UInt8] = [0x60, UInt8(tagList.count)] + tagList
        let groups = try IDVDataGroupParser.parseCOMTagList(com)
        #expect(groups.contains(.dg1))
        #expect(groups.contains(.dg2))
        #expect(groups.contains(.dg14))
    }
}
