//
//  IDVHex.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation

/// Hex helpers for pasting ICAO 9303 worked-example vectors into tests.
enum Hex {
    static func bytes(_ string: String) -> [UInt8] {
        let clean = string.filter(\.isHexDigit)
        var result = [UInt8]()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            result.append(UInt8(clean[index ..< next], radix: 16)!)
            index = next
        }
        return result
    }

    static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
