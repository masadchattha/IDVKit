//
//  IDVJPEG2000DecoderTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import Testing
import IDVKitCore
@testable import IDVKitJPEG2000

struct CodecSniffTests {
    @Test func socMarkerMeansRawCodestream() {
        let j2k = Data([0xFF, 0x4F, 0xFF, 0x51])
        #expect(IDVJPEG2000Decoder.sniffCodec(j2k) == .j2k)
    }

    @Test func jp2SignatureBoxMeansContainer() {
        let jp2 = Data([0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20])
        #expect(IDVJPEG2000Decoder.sniffCodec(jp2) == .jp2)
    }
}

struct DecodeTests {
    private func fixtureData() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "face_64x64", withExtension: "jp2"))
        return try Data(contentsOf: url)
    }

    @Test func decodesJP2Fixture() throws {
        let image = try IDVJPEG2000Decoder.decode(fixtureData())
        #expect(image.width == 64)
        #expect(image.height == 64)
        #expect(image.bitsPerComponent == 8)
    }

    @Test func emptyDataThrowsInsteadOfCrashing() {
        // The implementation this replaces called fatalError() here. Never again.
        #expect(throws: IDVError.jpeg2000DecodeFailed(detail: "empty data")) {
            try IDVJPEG2000Decoder.decode(Data())
        }
    }

    @Test func garbageDataThrowsInsteadOfCrashing() {
        let garbage = Data((0 ..< 256).map { UInt8($0 & 0xFF) })
        #expect(throws: IDVError.self) {
            try IDVJPEG2000Decoder.decode(garbage)
        }
    }

    @Test func truncatedFixtureThrowsInsteadOfCrashing() throws {
        let truncated = try fixtureData().prefix(200)
        #expect(throws: IDVError.self) {
            try IDVJPEG2000Decoder.decode(Data(truncated))
        }
    }
}
