//
//  VIDReadOperationTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Testing
import VerifIDCore
import VerifIDMRZ
@testable import VerifIDNFC

struct ReadOperationTests {
    @Test func parsesTotalObjectLengthShortForm() throws {
        // Tag 60, length 0x14 → total = 2 header + 20 value.
        let (total, header) = try VIDPassportReadOperation.totalObjectLength([0x60, 0x14, 0x5F, 0x01])
        #expect(total == 22)
        #expect(header == 2)
    }

    @Test func parsesTotalObjectLengthLongForm() throws {
        // Tag 75, length 0x82 0x01 0x00 → total = 4 header + 256 value.
        let (total, header) = try VIDPassportReadOperation.totalObjectLength([0x75, 0x82, 0x01, 0x00])
        #expect(total == 260)
        #expect(header == 4)
    }

    @Test func parsesMultiByteTagLength() throws {
        // Multi-byte tag 7F61, short length 0x10.
        let (total, header) = try VIDPassportReadOperation.totalObjectLength([0x7F, 0x61, 0x10, 0x00])
        #expect(total == 3 + 0x10)
        #expect(header == 3)
    }
}
