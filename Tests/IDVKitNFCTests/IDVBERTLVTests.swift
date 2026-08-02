//
//  IDVBERTLVTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import IDVKitCore
@testable import IDVKitNFC
import Testing

struct BERTLVTests {
    @Test func parsesShortFormSingleObject() throws {
        // Tag 5F1F (multi-byte), length 3, value 01 02 03.
        let bytes: [UInt8] = [0x5F, 0x1F, 0x03, 0x01, 0x02, 0x03]
        let (tlv, next) = try IDVBERTLV.parse(bytes)
        #expect(tlv.tag == [0x5F, 0x1F])
        #expect(tlv.tagNumber == 0x5F1F)
        #expect(tlv.value == [0x01, 0x02, 0x03])
        #expect(next == bytes.count)
    }

    @Test func parsesLongFormLength() throws {
        // Tag 75, length 0x81 0x80 (long form, 128 bytes).
        var bytes: [UInt8] = [0x75, 0x81, 0x80]
        bytes.append(contentsOf: Array(repeating: 0xAB, count: 128))
        let (tlv, _) = try IDVBERTLV.parse(bytes)
        #expect(tlv.tagNumber == 0x75)
        #expect(tlv.value.count == 128)
    }

    @Test func parsesNestedConstructedObject() throws {
        // 61 (constructed) → 5F1F length 2 value AA BB (inner is 5 bytes).
        let bytes: [UInt8] = [0x61, 0x05, 0x5F, 0x1F, 0x02, 0xAA, 0xBB]
        let (tlv, _) = try IDVBERTLV.parse(bytes)
        #expect(tlv.isConstructed)
        #expect(tlv.children.count == 1)
        let child = try #require(tlv.first(tag: 0x5F1F))
        #expect(child.value == [0xAA, 0xBB])
    }

    @Test func findsDeeplyNestedTag() throws {
        // DG2 shape: 75 → 7F61 → 7F60 → 5F2E value.
        let inner: [UInt8] = [0x5F, 0x2E, 0x02, 0x01, 0x02]
        let l60 = [0x7F, 0x60, UInt8(inner.count)] + inner
        let l61 = [0x7F, 0x61, UInt8(l60.count)] + l60
        let dg2 = [UInt8(0x75), UInt8(l61.count)] + l61
        let (tlv, _) = try IDVBERTLV.parse(dg2)
        let image = try #require(tlv.first(tag: 0x5F2E))
        #expect(image.value == [0x01, 0x02])
    }

    @Test func throwsOnTruncatedValue() {
        let bytes: [UInt8] = [0x5F, 0x1F, 0x05, 0x01] // claims 5 bytes, has 1
        #expect(throws: IDVError.self) {
            _ = try IDVBERTLV.parse(bytes)
        }
    }

    @Test func parsesConsecutiveObjects() throws {
        // Two objects back to back.
        let bytes: [UInt8] = [0x5F, 0x01, 0x01, 0xAA, 0x5F, 0x02, 0x01, 0xBB]
        let all = try IDVBERTLV.parseAll(bytes)
        #expect(all.count == 2)
        #expect(all[0].value == [0xAA])
        #expect(all[1].value == [0xBB])
    }
}
