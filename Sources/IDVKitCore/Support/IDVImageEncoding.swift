//
//  IDVImageEncoding.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension CGImage {
    /// JPEG-encodes the image via ImageIO — the single JPEG encoder used across
    /// the SDK (no UIKit dependency, one compression-quality policy).
    ///
    /// - Parameter quality: Compression quality, `0`…`1` (default `0.9`).
    /// - Returns: JPEG data, or `nil` if encoding fails.
    package func idvJPEGData(quality: CGFloat = 0.9) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, self,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
