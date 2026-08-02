//
//  IDVError.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation

/// Every IDVKit failure is a typed, thrown error.
/// The SDK never calls `fatalError` and never stalls silently.
public enum IDVError: Error, Sendable, Equatable {
    // MARK: MRZ

    /// No checksum-valid MRZ was recognized within the configured timeout.
    case mrzScanTimeout
    /// The text is not a structurally valid MRZ.
    case mrzInvalidFormat(detail: String)
    /// An ICAO 9303 check digit did not verify for the named field.
    case mrzChecksumFailed(field: String)

    // MARK: NFC

    /// This device has no NFC reading capability.
    case nfcNotSupported
    case nfcSessionFailed(detail: String)
    case nfcTagConnectionLost
    /// BAC/PACE failed — usually a wrong MRZ key (typo, unreadable MRZ).
    case accessControlFailed(detail: String)
    case dataGroupReadFailed(String)
    /// The chip's data could not be proven genuine.
    case passiveAuthenticationFailed(detail: String)

    // MARK: Imaging

    case jpeg2000DecodeFailed(detail: String)

    // MARK: Face

    case cameraPermissionDenied
    /// Device lacks TrueDepth and the passive-liveness fallback is disabled.
    case faceTrackingUnsupported
    case livenessTimeout
    case livenessFailed(detail: String)
    /// No face found in the named image (`"reference"` or `"live"`).
    case noFaceDetected(inImage: String)
    /// More than one face was found in the named image — verification requires
    /// exactly one subject in view.
    case multipleFacesDetected(inImage: String)
    case faceMatchBelowThreshold(similarity: Float)
    case modelLoadFailed(detail: String)

    // MARK: Flow

    case cancelledByUser
    case configurationInvalid(detail: String)
}

extension IDVError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .mrzScanTimeout: "Could not read the machine-readable zone in time."
        case let .mrzInvalidFormat(d): "The scanned MRZ is not valid: \(d)"
        case let .mrzChecksumFailed(f): "MRZ check digit failed for \(f)."
        case .nfcNotSupported: "This device does not support NFC passport reading."
        case let .nfcSessionFailed(d): "NFC session failed: \(d)"
        case .nfcTagConnectionLost: "Connection to the passport chip was lost."
        case let .accessControlFailed(d): "Could not authenticate with the chip: \(d)"
        case let .dataGroupReadFailed(dg): "Failed to read \(dg) from the chip."
        case let .passiveAuthenticationFailed(d): "Chip authenticity could not be verified: \(d)"
        case let .jpeg2000DecodeFailed(d): "Could not decode the chip photo: \(d)"
        case .cameraPermissionDenied: "Camera access is required."
        case .faceTrackingUnsupported: "Face tracking is not supported on this device."
        case .livenessTimeout: "Liveness check timed out."
        case let .livenessFailed(d): "Liveness check failed: \(d)"
        case let .noFaceDetected(which): "No face was detected in the \(which) image."
        case .multipleFacesDetected: "More than one face is in view — make sure you're the only person visible."
        case .faceMatchBelowThreshold: "The face did not match the document photo."
        case let .modelLoadFailed(d): "Face model could not be loaded: \(d)"
        case .cancelledByUser: "Cancelled."
        case let .configurationInvalid(d): "Invalid configuration: \(d)"
        }
    }
}
