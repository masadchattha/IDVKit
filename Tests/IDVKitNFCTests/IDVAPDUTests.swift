//
//  IDVAPDUTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import IDVKitCore
@testable import IDVKitNFC
import Testing

struct APDUTests {
    @Test func encodesSelectByFileID() {
        // SELECT (00 A4 02 0C) EF.COM (01 1E).
        let apdu = IDVCommandAPDU(cla: 0x00, ins: 0xA4, p1: 0x02, p2: 0x0C,
                                  data: [0x01, 0x1E], expectedResponseLength: 0)
        #expect(apdu.encoded == [0x00, 0xA4, 0x02, 0x0C, 0x02, 0x01, 0x1E])
    }

    @Test func encodesReadBinaryWithLe() {
        // READ BINARY (00 B0 00 00) first 4 bytes.
        let apdu = IDVCommandAPDU(cla: 0x00, ins: 0xB0, p1: 0x00, p2: 0x00,
                                  data: [], expectedResponseLength: 4)
        #expect(apdu.encoded == [0x00, 0xB0, 0x00, 0x00, 0x04])
    }

    @Test func encodesLe256AsZero() {
        let apdu = IDVCommandAPDU(cla: 0x00, ins: 0xB0, p1: 0x00, p2: 0x00,
                                  expectedResponseLength: 256)
        #expect(apdu.encoded.last == 0x00)
    }

    @Test func successStatusWord() throws {
        let response = IDVResponseAPDU(data: [0x01, 0x02], sw1: 0x90, sw2: 0x00)
        #expect(response.isSuccess)
        #expect(response.statusWord == 0x9000)
        try response.checkSuccess()
    }

    @Test func failureStatusWordThrows() {
        let response = IDVResponseAPDU(data: [], sw1: 0x69, sw2: 0x82) // security status not satisfied
        #expect(!response.isSuccess)
        #expect(throws: IDVError.self) {
            try response.checkSuccess()
        }
    }
}
