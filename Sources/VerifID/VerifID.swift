//
//  VerifID.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//
//  Passport NFC + MRZ + face match + liveness, 100% on-device.
//  No API keys. No server. Nothing leaves the phone.
//

@_exported import VerifIDCore
@_exported import VerifIDFace
@_exported import VerifIDMRZ
@_exported import VerifIDNFC
@_exported import VerifIDUI

/// Package-level metadata.
public enum VerifID {
    /// The SDK version, mirroring the release tag.
    public static let version = "0.1.0-dev"
}
