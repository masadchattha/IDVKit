//
//  VIDConfiguration.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation

/// Root configuration for a verification flow.
///
/// All defaults are production-sane — `VIDConfiguration.default` works out of
/// the box. Every threshold, timeout and message the SDK uses is reachable
/// from here; nothing is hardcoded.
public struct VIDConfiguration: Sendable {
    /// The steps the flow runs, in order.
    public var steps: [VIDVerificationStep]
    /// MRZ camera-scanner options.
    public var mrz: VIDMRZConfiguration
    /// NFC chip-reading and chip-authenticity options.
    public var nfc: VIDNFCConfiguration
    /// Face-match and liveness options.
    public var face: VIDFaceConfiguration
    /// Drop-in flow UI options (intro, data review, branding).
    public var ui: VIDUIConfiguration

    /// The recommended full flow: document scan → chip read → face match.
    public static let `default` = VIDConfiguration()

    public init(
        steps: [VIDVerificationStep] = [.documentScan(.any), .nfcChipRead, .faceMatch],
        mrz: VIDMRZConfiguration = .init(),
        nfc: VIDNFCConfiguration = .init(),
        face: VIDFaceConfiguration = .init(),
        ui: VIDUIConfiguration = .init()
    ) {
        self.steps = steps
        self.mrz = mrz
        self.nfc = nfc
        self.face = face
        self.ui = ui
    }
}

/// One stage of the verification flow.
public enum VIDVerificationStep: Sendable, Equatable {
    /// An ICAO 9303 machine-readable travel document. All are read the same way
    /// over NFC — the MRZ layout differs (passport = TD3, ID card / residence
    /// permit = TD1 or TD2) but the SDK auto-detects it while scanning.
    public enum DocumentKind: Sendable, Hashable {
        /// Passport booklet (TD3 MRZ).
        case passport
        /// National ID card (usually TD1, sometimes TD2).
        case idCard
        /// Residence permit (TD1).
        case residencePermit
        /// Any supported document — the scanner detects the exact layout.
        case any
    }

    case documentScan(DocumentKind)
    case nfcChipRead
    case faceMatch
}

// MARK: - MRZ

/// Options for the camera MRZ scanner.
public struct VIDMRZConfiguration: Sendable {
    /// Seconds before one scan attempt gives up.
    public var scanTimeout: TimeInterval
    /// Attempts before the flow offers manual entry.
    public var maxScanAttempts: Int
    /// Whether the manual-entry fallback screen is offered at all.
    public var allowManualEntry: Bool
    /// Whether the torch toggle is shown in the scanner UI.
    public var showsTorchButton: Bool
    /// Shapes the on-screen guide to the document being scanned (passport data
    /// page vs. ID-1 card). Recognition still auto-detects the MRZ layout — this
    /// only sizes the reticle. `.any` uses a neutral card shape that fits both.
    public var documentKind: VIDVerificationStep.DocumentKind
    /// The document types the drop-in flow lets the user choose between.
    ///
    /// When this lists **two or more concrete kinds** (anything other than
    /// `.any`), the flow shows a document-type picker before scanning and shapes
    /// the reticle to the chosen document. With one kind — or the default
    /// `[.any]` — no picker appears and the scanner simply auto-detects the MRZ
    /// layout. Recognition is always auto-detecting; this only drives the UI.
    public var allowedDocuments: [VIDVerificationStep.DocumentKind]

    public init(
        scanTimeout: TimeInterval = 20,
        maxScanAttempts: Int = 3,
        allowManualEntry: Bool = true,
        showsTorchButton: Bool = true,
        documentKind: VIDVerificationStep.DocumentKind = .any,
        allowedDocuments: [VIDVerificationStep.DocumentKind] = [.any]
    ) {
        self.scanTimeout = scanTimeout
        self.maxScanAttempts = maxScanAttempts
        self.allowManualEntry = allowManualEntry
        self.showsTorchButton = showsTorchButton
        self.documentKind = documentKind
        self.allowedDocuments = allowedDocuments
    }

    /// The concrete, user-selectable document kinds — `allowedDocuments` with
    /// `.any` removed, preserving order and dropping duplicates.
    public var selectableDocuments: [VIDVerificationStep.DocumentKind] {
        var seen = Set<VIDVerificationStep.DocumentKind>()
        return allowedDocuments.filter { $0 != .any && seen.insert($0).inserted }
    }

    /// Whether the drop-in flow shows a document-type picker before scanning.
    /// True only when the user has a real choice (two or more concrete kinds).
    public var offersDocumentChoice: Bool {
        selectableDocuments.count >= 2
    }
}

// MARK: - NFC

/// Options for the passport chip reader.
public struct VIDNFCConfiguration: Sendable {
    /// Chip-genuineness verification policy (ICAO Doc 9303 Part 11 §5.1).
    ///
    /// Passive authentication has two independent halves:
    /// - **Data integrity** — the data-group hashes match the SOD and the SOD's
    ///   signature is valid. This needs no trust store and always runs.
    /// - **Chain trust** — the Document Signer Certificate chains to a trusted
    ///   CSCA. This needs a CSCA trust store you supply.
    ///
    /// VerifID reports the two halves separately so an app without a trust store
    /// still gets integrity verification instead of a misleading "failed".
    public enum PassiveAuthentication: Sendable {
        /// Verify data integrity **and** the DSC→CSCA chain against the supplied
        /// CSCA trust anchors (see ``VIDTrustStore``).
        case enabled(cscaTrustStore: VIDTrustStore)
        /// Verify data integrity only; report chain trust as not performed.
        /// The sensible default until you supply a CSCA trust store.
        case integrityOnly
        /// Skip passive authentication entirely. Strongly discouraged.
        case disabled
    }

    /// Read stages, used to key custom Apple-NFC-sheet messages.
    public enum ReadStep: Sendable, Equatable {
        case holdNearPassport
        case authenticating
        case readingDataGroup(String, progress: Double)
        case success
        case failure
    }

    /// Which chip-access protocol to use to open the secure channel.
    public enum AccessProtocol: Sendable {
        /// Prefer PACE when the chip advertises it (EF.CardAccess), else BAC. Default.
        case automatic
        /// Use PACE only; fail if the chip does not support a supported PACE profile.
        case paceOnly
        /// Use BAC only.
        case bacOnly
    }

    /// Which data groups to request from the chip.
    public var readDataGroups: [VIDDataGroupID]
    /// Secure-channel selection: PACE, BAC, or automatic (PACE with BAC fallback).
    public var accessProtocol: AccessProtocol
    /// Chip-authenticity policy — integrity-only, full chain-of-trust, or off.
    public var passiveAuthentication: PassiveAuthentication
    /// Customize the text in Apple's NFC bottom sheet for every step —
    /// including localization and branding. Return `nil` from the closure to
    /// keep VerifID's localized default for that step.
    public var displayMessage: (@Sendable (ReadStep) -> String?)?

    public init(
        readDataGroups: [VIDDataGroupID] = [.com, .dg1, .dg2, .dg7, .dg11, .dg12, .dg14, .sod],
        accessProtocol: AccessProtocol = .automatic,
        passiveAuthentication: PassiveAuthentication = .integrityOnly,
        displayMessage: (@Sendable (ReadStep) -> String?)? = nil
    ) {
        self.readDataGroups = readDataGroups
        self.accessProtocol = accessProtocol
        self.passiveAuthentication = passiveAuthentication
        self.displayMessage = displayMessage
    }
}

// MARK: - Face

/// Options for liveness detection and face matching.
public struct VIDFaceConfiguration: Sendable {
    public enum ChallengeSelection: Sendable, Equatable {
        /// Pick `count` random challenges per session (recommended —
        /// unpredictability is part of the anti-spoofing).
        case random(count: Int)
        case fixed([VIDLivenessChallenge])
    }

    /// Cosine-similarity decision threshold, calibrated for MobileFaceNet
    /// embeddings. Raise for stricter matching (more false rejections),
    /// lower for laxer matching (more false accepts).
    public var matchThreshold: Float
    /// Which liveness strategy the capture runs. Defaults to
    /// ``VIDLivenessMode/headRotation`` — the strongest anti-spoof on a
    /// TrueDepth device and free of any "turn left/right" ambiguity.
    public var livenessMode: VIDLivenessMode
    /// Whether a short coaching tutorial is shown before liveness begins.
    public var showsTutorial: Bool
    /// How the (optional) active challenges are chosen (random count, or a fixed
    /// list). Only consulted when ``livenessMode`` includes active challenges.
    public var challenges: ChallengeSelection
    /// Seconds allowed per individual challenge.
    public var challengeTimeout: TimeInterval
    /// Seconds allowed for the whole liveness session.
    public var sessionTimeout: TimeInterval
    /// Full-session retries before the flow fails.
    public var maxRetries: Int
    /// Anti-spoofing gate: natural head sway (yaw standard deviation over
    /// ~0.5 s) must exceed this. Flat photos and screens sit near zero.
    public var microMovementThreshold: Float
    /// **Debug/testing only.** When `true`, the face-intro screen offers a
    /// "choose a photo" option so developers can run the match against a library
    /// image instead of the live camera (handy in the simulator or poor light).
    /// The option is compiled out of release builds, so this flag is a no-op
    /// unless the SDK is built in a `DEBUG` configuration.
    public var allowsDebugPhotoMatch: Bool

    public init(
        matchThreshold: Float = 0.65,
        livenessMode: VIDLivenessMode = .headRotation,
        showsTutorial: Bool = true,
        challenges: ChallengeSelection = .random(count: 2),
        challengeTimeout: TimeInterval = 10,
        sessionTimeout: TimeInterval = 90,
        maxRetries: Int = 3,
        microMovementThreshold: Float = 0.002,
        allowsDebugPhotoMatch: Bool = false
    ) {
        self.matchThreshold = matchThreshold
        self.livenessMode = livenessMode
        self.showsTutorial = showsTutorial
        self.challenges = challenges
        self.challengeTimeout = challengeTimeout
        self.sessionTimeout = sessionTimeout
        self.maxRetries = maxRetries
        self.microMovementThreshold = microMovementThreshold
        self.allowsDebugPhotoMatch = allowsDebugPhotoMatch
    }
}

/// The liveness strategy used during selfie capture.
///
/// The default, ``headRotation``, is where the industry (and Apple's Face ID
/// enrollment) has converged: the user rotates their head to fill a ring, which
/// on a TrueDepth device is a genuine 3D-presence signal and avoids the
/// mirror-vs-anatomical "turn left/right" confusion of verbal challenges.
public enum VIDLivenessMode: String, Sendable, CaseIterable {
    /// Head-rotation ring only, plus the passive micro-movement anti-spoof gate.
    /// Recommended default.
    case headRotation
    /// Randomised active challenges only (blink, smile, open mouth, head turn).
    case activeChallenges
    /// Active challenges first, then the head-rotation ring.
    case both
    /// No user actions — relies solely on the passive micro-movement gate and
    /// (on TrueDepth) depth. Smoothest, but leans hardest on the anti-spoof gate.
    case passive

    /// Whether this mode runs the randomised active challenges.
    public var usesActiveChallenges: Bool {
        self == .activeChallenges || self == .both
    }

    /// Whether this mode runs the head-rotation ring phase.
    public var usesHeadRotation: Bool {
        self == .headRotation || self == .both
    }
}

/// Gestures the user can be asked to perform during active liveness.
public enum VIDLivenessChallenge: String, Sendable, CaseIterable {
    case blinkLeft, blinkRight, smile, openMouth, turnLeft, turnRight
}

// MARK: - UI

/// Options for the drop-in flow UI.
public struct VIDUIConfiguration: Sendable {
    /// Whether the flow opens with the intro screen.
    public var showIntro: Bool
    /// Whether the parsed passport data is shown for user confirmation.
    public var showDataReview: Bool
    /// Whether success/failure haptics fire during the flow.
    public var hapticsEnabled: Bool
    /// Whether to surface low-level security diagnostics in the result UI — the
    /// "chip data intact" state and the CSCA-trust-store detail (e.g. which CSCA
    /// to add). Off by default: end users only see plain-language verdicts.
    /// Turn on for developer/debug builds. The full breakdown is always available
    /// on the returned `VIDVerificationOutcome` regardless of this flag.
    public var showsSecurityDetails: Bool
    /// Host-app branding shown throughout the flow.
    public var branding: VIDBrandingConfiguration
    /// Optional custom artwork for the flow's hero screens.
    public var illustrations: VIDIllustrations

    public init(
        showIntro: Bool = true,
        showDataReview: Bool = true,
        hapticsEnabled: Bool = true,
        showsSecurityDetails: Bool = false,
        branding: VIDBrandingConfiguration = .init(),
        illustrations: VIDIllustrations = .init()
    ) {
        self.showIntro = showIntro
        self.showDataReview = showDataReview
        self.hapticsEnabled = hapticsEnabled
        self.showsSecurityDetails = showsSecurityDetails
        self.branding = branding
        self.illustrations = illustrations
    }
}

/// Optional custom artwork for the flow's hero screens.
///
/// Each slot is `nil` by default, in which case the screen shows a built-in
/// SF Symbol inside a tinted circle. Supply PNG data — ideally a **square,
/// transparent-background illustration around 240×240 pt (720 px @3x)** — to
/// replace the symbol with your own art. Anything you don't set keeps the
/// default symbol, so you can brand one screen or all of them.
public struct VIDIllustrations: Sendable {
    /// Intro screen ("Verify your identity").
    public var intro: Data?
    /// Document-scan guidance screen ("Scan your document").
    public var documentScan: Data?
    /// Chip-guidance screen ("Now read the chip"). `nil` shows the built-in
    /// animated NFC tap.
    public var chipGuidance: Data?
    /// Face-intro screen ("Now let's check it's you").
    public var faceIntro: Data?

    public init(
        intro: Data? = nil,
        documentScan: Data? = nil,
        chipGuidance: Data? = nil,
        faceIntro: Data? = nil
    ) {
        self.intro = intro
        self.documentScan = documentScan
        self.chipGuidance = chipGuidance
        self.faceIntro = faceIntro
    }
}

/// Host-app branding for the drop-in flow: your icon and product name appear
/// on the intro and result screens, so the verification feels native to your
/// app rather than a third-party interruption.
public struct VIDBrandingConfiguration: Sendable {
    /// Your app icon or logo as image data (PNG/JPEG). Shown on the intro
    /// screen and NFC guidance. `nil` hides the slot.
    public var logoImageData: Data?
    /// Your product name, e.g. shown as "Acme verifies your identity".
    /// `nil` falls back to the app's display name.
    public var appName: String?
    /// Shows a subtle "Secured on-device by VerifID" footer. Keeping it on
    /// supports the open-source project — thank you. Off is fine too.
    public var showsPoweredByBadge: Bool

    public init(
        logoImageData: Data? = nil,
        appName: String? = nil,
        showsPoweredByBadge: Bool = true
    ) {
        self.logoImageData = logoImageData
        self.appName = appName
        self.showsPoweredByBadge = showsPoweredByBadge
    }
}
