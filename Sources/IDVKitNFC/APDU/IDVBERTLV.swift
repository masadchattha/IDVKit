//
//  IDVBERTLV.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore

/// A parsed BER-TLV (ISO 7816-4 / ISO 8825-1) data object.
///
/// eMRTD data groups are nested BER-TLV structures; this type parses the tag,
/// length (short and long forms) and value, and recurses into constructed
/// objects. Tags are kept as their raw byte sequence (`0x5F1F`, `0x7F61`, …)
/// so multi-byte tags compare exactly.
struct IDVBERTLV: Equatable {
    /// The tag bytes, big-endian as they appear on the wire (e.g. `[0x5F, 0x1F]`).
    let tag: [UInt8]
    /// The value bytes (the V of TLV).
    let value: [UInt8]
    /// Child objects, when the tag's constructed bit (0x20) is set.
    let children: [IDVBERTLV]

    /// The tag rendered as a single integer for convenient matching
    /// (e.g. `0x5F1F`). Valid for tags up to 4 bytes, which covers eMRTD.
    var tagNumber: UInt32 {
        tag.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    var isConstructed: Bool {
        guard let first = tag.first else { return false }
        return first & 0x20 != 0
    }

    // MARK: Parsing

    /// Parses a single top-level TLV object from `bytes` starting at `offset`.
    /// - Returns: the object and the index just past it.
    /// - Throws: ``IDVError/dataGroupReadFailed(_:)`` on malformed encoding.
    static func parse(_ bytes: [UInt8], from offset: Int = 0) throws -> (tlv: IDVBERTLV, next: Int) {
        var index = offset

        let tag = try parseTag(bytes, &index)
        let length = try parseLength(bytes, &index)

        guard index + length <= bytes.count else {
            throw IDVError.dataGroupReadFailed("TLV value length \(length) exceeds available bytes")
        }
        let value = Array(bytes[index ..< index + length])
        index += length

        let constructed = (tag.first ?? 0) & 0x20 != 0
        let children = constructed ? (try? parseAll(value)) ?? [] : []

        return (IDVBERTLV(tag: tag, value: value, children: children), index)
    }

    /// Parses every consecutive TLV object in `bytes`.
    static func parseAll(_ bytes: [UInt8]) throws -> [IDVBERTLV] {
        var result: [IDVBERTLV] = []
        var index = 0
        while index < bytes.count {
            // Skip 0x00 / 0xFF padding bytes between objects.
            if bytes[index] == 0x00 || bytes[index] == 0xFF {
                index += 1
                continue
            }
            let (tlv, next) = try parse(bytes, from: index)
            result.append(tlv)
            index = next
        }
        return result
    }

    /// Depth-first search for the first descendant (or self) with `tagNumber`.
    func first(tag target: UInt32) -> IDVBERTLV? {
        if tagNumber == target {
            return self
        }
        for child in children {
            if let found = child.first(tag: target) {
                return found
            }
        }
        return nil
    }

    // MARK: Tag / length decoding

    private static func parseTag(_ bytes: [UInt8], _ index: inout Int) throws -> [UInt8] {
        guard index < bytes.count else {
            throw IDVError.dataGroupReadFailed("truncated TLV tag")
        }
        var tag = [bytes[index]]
        // Multi-byte tag: low 5 bits of the first byte all set (0x1F).
        if bytes[index] & 0x1F == 0x1F {
            repeat {
                index += 1
                guard index < bytes.count else {
                    throw IDVError.dataGroupReadFailed("truncated multi-byte TLV tag")
                }
                tag.append(bytes[index])
            } while bytes[index] & 0x80 != 0 // high bit set → another tag byte follows
        }
        index += 1
        return tag
    }

    private static func parseLength(_ bytes: [UInt8], _ index: inout Int) throws -> Int {
        guard index < bytes.count else {
            throw IDVError.dataGroupReadFailed("truncated TLV length")
        }
        let first = bytes[index]
        index += 1

        if first & 0x80 == 0 {
            return Int(first) // short form
        }

        // Long form: low 7 bits give the number of subsequent length bytes.
        let byteCount = Int(first & 0x7F)
        guard byteCount > 0, byteCount <= 4 else {
            throw IDVError.dataGroupReadFailed("unsupported TLV length form (\(byteCount) bytes)")
        }
        guard index + byteCount <= bytes.count else {
            throw IDVError.dataGroupReadFailed("truncated long-form TLV length")
        }
        var length = 0
        for _ in 0 ..< byteCount {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }
}
