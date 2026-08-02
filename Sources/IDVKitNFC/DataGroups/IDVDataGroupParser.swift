//
//  IDVDataGroupParser.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore
import IDVKitMRZ

/// Parses eMRTD data-group byte streams (ICAO Doc 9303 Part 10) into IDVKit
/// value types. All parsers tolerate the length/structure variations seen
/// across issuing states and never crash on malformed input.
enum IDVDataGroupParser {
    /// eMRTD elementary file identifiers (ICAO 9303 Part 10, Table 3).
    enum File {
        static let cardAccess: [UInt8] = [0x01, 0x1C]
        static let com: [UInt8] = [0x01, 0x1E]
        static let dg1: [UInt8] = [0x01, 0x01]
        static let dg2: [UInt8] = [0x01, 0x02]
        static let dg7: [UInt8] = [0x01, 0x07]
        static let dg11: [UInt8] = [0x01, 0x0B]
        static let dg12: [UInt8] = [0x01, 0x0C]
        static let dg14: [UInt8] = [0x01, 0x0E]
        static let dg15: [UInt8] = [0x01, 0x0F]
        static let sod: [UInt8] = [0x01, 0x1D]

        /// The elementary-file identifier for a given data-group id.
        static func identifier(for group: IDVDataGroupID) -> [UInt8]? {
            switch group {
            case .com: com
            case .dg1: dg1
            case .dg2: dg2
            case .dg7: dg7
            case .dg11: dg11
            case .dg12: dg12
            case .dg14: dg14
            case .dg15: dg15
            case .sod: sod
            }
        }
    }

    /// Parses DG1 (tag 61 → 5F1F) into structured MRZ data. The MRZ body is
    /// the concatenated MRZ lines with line breaks removed; this splits TD3
    /// (2×44) and delegates field parsing to ``IDVMRZParser``.
    static func parseDG1(_ bytes: [UInt8]) throws -> IDVMRZData {
        let root = try IDVBERTLV.parse(bytes).tlv
        guard let mrzTLV = root.first(tag: 0x5F1F) else {
            throw IDVError.dataGroupReadFailed("DG1 missing MRZ (tag 5F1F)")
        }
        let mrzString = String(decoding: mrzTLV.value, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch mrzString.count {
        case 88: // TD3: two lines of 44
            let line1 = String(mrzString.prefix(44))
            let line2 = String(mrzString.suffix(44))
            return try IDVMRZParser.parseTD3(line1: line1, line2: line2)
        default:
            throw IDVError.dataGroupReadFailed("unsupported MRZ length \(mrzString.count) in DG1")
        }
    }

    /// Extracts the encoded face image from DG2 (ICAO 9303 Part 10 + ISO 19794-5).
    ///
    /// DG2 nests: 75 → 7F61 → 7F60 → biometric header + 5F2E (or 7F2E) image
    /// block. Rather than trust every issuer's exact ISO 19794-5 header length,
    /// this scans the image block for the JPEG/JPEG2000 magic bytes — robust
    /// across the header variants seen in the wild.
    ///
    /// - Returns: the raw image bytes and whether they are JPEG2000.
    static func parseDG2FaceImage(_ bytes: [UInt8]) throws -> (imageData: [UInt8], isJPEG2000: Bool) {
        let root = try IDVBERTLV.parse(bytes).tlv
        guard let imageBlock = root.first(tag: 0x5F2E) ?? root.first(tag: 0x7F2E) else {
            throw IDVError.dataGroupReadFailed("DG2 missing biometric image block (5F2E/7F2E)")
        }
        return try locateImage(in: imageBlock.value)
    }

    /// Finds the start of a JPEG or JPEG2000 stream within an ISO 19794-5
    /// face record and returns from there to the end.
    static func locateImage(in block: [UInt8]) throws -> (imageData: [UInt8], isJPEG2000: Bool) {
        // JPEG2000 codestream (SOC): FF 4F FF 51
        if let range = firstIndex(of: [0xFF, 0x4F, 0xFF, 0x51], in: block) {
            return (Array(block[range...]), true)
        }
        // JPEG2000 JP2 container signature box.
        if let range = firstIndex(of: [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20], in: block) {
            return (Array(block[range...]), true)
        }
        // JPEG (SOI): FF D8 FF
        if let range = firstIndex(of: [0xFF, 0xD8, 0xFF], in: block) {
            return (Array(block[range...]), false)
        }
        throw IDVError.dataGroupReadFailed("no JPEG/JPEG2000 image found in DG2")
    }

    /// Parses COM's tag-list (tag 60 → 5C) into the set of present data groups.
    static func parseCOMTagList(_ bytes: [UInt8]) throws -> [IDVDataGroupID] {
        let root = try IDVBERTLV.parse(bytes).tlv
        guard let tagList = root.first(tag: 0x5C) else { return [] }
        // 5C is a list of one-byte DG tags (61, 75, …); map each to its id.
        return tagList.value.compactMap { dgTag in
            switch dgTag {
            case 0x61: .dg1
            case 0x75: .dg2
            case 0x67: .dg7
            case 0x6B: .dg11
            case 0x6C: .dg12
            case 0x6E: .dg14
            case 0x6F: .dg15
            default: nil
            }
        }
    }

    private static func firstIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard pattern.count <= bytes.count else { return nil }
        for start in 0 ... (bytes.count - pattern.count) where Array(bytes[start ..< start + pattern.count]) == pattern {
            return start
        }
        return nil
    }
}
