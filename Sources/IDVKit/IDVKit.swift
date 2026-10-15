//
//  IDVKit.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//
//  Passport NFC + MRZ + face match + liveness, 100% on-device.
//  No API keys. No server. Nothing leaves the phone.
//

@_exported import IDVKitCore
@_exported import IDVKitFace
@_exported import IDVKitMRZ
@_exported import IDVKitNFC
@_exported import IDVKitUI

/// Package-level metadata.
public enum IDVKit {
    /// The SDK version, mirroring the release tag.
    public static let version = "1.0.0"
}
