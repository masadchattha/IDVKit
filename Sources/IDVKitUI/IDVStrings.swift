//
//  IDVStrings.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import SwiftUI

/// All display copy for the drop-in UI, centralized. Values are
/// `LocalizedStringKey`, so the flow stays localizable through the module's
/// `Localizable.xcstrings` (the constant's value is the catalog key) while no
/// copy is hardcoded inline in a view body.
///
/// Each constant is `nonisolated(unsafe)`: `LocalizedStringKey` isn't
/// `Sendable`, but these are compile-time string literals assigned once and
/// never mutated, so sharing them across isolation domains is safe.
enum IDVStrings {
    enum Intro {
        nonisolated(unsafe) static let title: LocalizedStringKey = "Verify your identity"
        nonisolated(unsafe) static let subtitle: LocalizedStringKey = "Scan your passport or ID, read its chip, and confirm it's really you. Everything happens on this device."
    }

    enum DocumentSelection {
        nonisolated(unsafe) static let title: LocalizedStringKey = "Choose your document"
        nonisolated(unsafe) static let subtitle: LocalizedStringKey = "Pick the ID you'd like to scan. We'll guide you through it."
    }

    enum ScanGuidance {
        nonisolated(unsafe) static let title: LocalizedStringKey = "Scan your document"
        nonisolated(unsafe) static let subtitle: LocalizedStringKey = "Rest it on a flat surface and fit it inside the frame. Keep the machine-readable lines at the bottom clear and well lit."
        nonisolated(unsafe) static let chipNotePassport: LocalizedStringKey = "Your passport needs an NFC chip. Look for this symbol on the cover."
        nonisolated(unsafe) static let chipNoteCard: LocalizedStringKey = "Your document needs an NFC chip. Look for this symbol on the front or back."
        nonisolated(unsafe) static let chipNoteGeneric: LocalizedStringKey = "Your document needs an NFC chip. Look for this symbol on it."
    }

    enum ChipGuidance {
        nonisolated(unsafe) static let title: LocalizedStringKey = "Now read the chip"
        nonisolated(unsafe) static let subtitle: LocalizedStringKey = "Your document has an NFC chip. Keep it flat on a surface."
        nonisolated(unsafe) static let rowRest: LocalizedStringKey = "Rest the top of your iPhone on the document."
        nonisolated(unsafe) static let rowHoldStill: LocalizedStringKey = "Hold still until the read completes."
        nonisolated(unsafe) static let rowCase: LocalizedStringKey = "Using a thick or metal case? Remove it if the read won't start."
    }

    enum ReadingChip {
        nonisolated(unsafe) static let title: LocalizedStringKey = "Reading your passport…"
        nonisolated(unsafe) static let subtitle: LocalizedStringKey = "Hold your iPhone against the passport until reading completes."
    }

    enum FaceIntro {
        nonisolated(unsafe) static let title: LocalizedStringKey = "Now let's check it's you"
        nonisolated(unsafe) static let subtitle: LocalizedStringKey = "Follow a couple of quick prompts so we can match your face to the photo in your document. It only takes a moment."
    }

    enum DocumentIssue {
        nonisolated(unsafe) static let notAcceptedTitle: LocalizedStringKey = "That document isn't accepted"

        /// "This looks like a passport, which isn't accepted here. Please scan a
        /// supported document." Not a `LocalizedStringKey` — the detected
        /// document's noun is only known at runtime, so the view renders it with
        /// `Text(verbatim:)` like the rest of this dynamic copy.
        static func notAcceptedBody(_ detectedNoun: String) -> String {
            "This looks like \(detectedNoun), which isn't accepted here. Please scan a supported document."
        }

        enum PickMismatch {
            static func title(_ detectedNoun: String) -> String {
                "That looks like \(detectedNoun)"
            }

            static func body(picked pickedNoun: String, detected detectedNoun: String) -> String {
                "You chose \(pickedNoun), but this is \(detectedNoun). Continue with it, or pick the right type."
            }
        }
    }

    enum Result {
        nonisolated(unsafe) static let couldNotRead: LocalizedStringKey = "Could not read your passport"

        enum Row {
            nonisolated(unsafe) static let document: LocalizedStringKey = "Document"
            nonisolated(unsafe) static let nationality: LocalizedStringKey = "Nationality"
            nonisolated(unsafe) static let sex: LocalizedStringKey = "Sex"
            nonisolated(unsafe) static let dateOfBirth: LocalizedStringKey = "Date of birth"
            nonisolated(unsafe) static let expiry: LocalizedStringKey = "Expiry"
        }
    }

    enum Badge {
        nonisolated(unsafe) static let mrzMatchesChip: LocalizedStringKey = "Scanned MRZ matches the chip"
        nonisolated(unsafe) static let chipVerified: LocalizedStringKey = "Chip verified"
        nonisolated(unsafe) static let chipDataIntact: LocalizedStringKey = "Chip data intact"
        nonisolated(unsafe) static let chipUnverifiable: LocalizedStringKey = "Chip could not be verified"
        nonisolated(unsafe) static let genuineChip: LocalizedStringKey = "Genuine chip confirmed"
        nonisolated(unsafe) static let chipAuthFailed: LocalizedStringKey = "Chip authenticity check failed"
        nonisolated(unsafe) static let faceMatches: LocalizedStringKey = "Face matches the document"
        nonisolated(unsafe) static let faceMismatch: LocalizedStringKey = "Face did not match"

        /// Developer-facing security detail, e.g. "similarity 0.87 / threshold 0.75".
        static func similarityDetail(_ similarity: Float, threshold: Float) -> String {
            "similarity \(String(format: "%.2f", similarity)) / threshold \(String(format: "%.2f", threshold))"
        }
    }

    enum FaceCapture {
        nonisolated(unsafe) static let positionFace: LocalizedStringKey = "Position your face in the oval"
        nonisolated(unsafe) static let lookStraight: LocalizedStringKey = "Look straight at the camera"
        nonisolated(unsafe) static let holdStill: LocalizedStringKey = "Hold still…"
        nonisolated(unsafe) static let verifying: LocalizedStringKey = "Verifying…"
        nonisolated(unsafe) static let multipleFacesWarning: LocalizedStringKey = "Only one face should be visible"
        nonisolated(unsafe) static let lowLightWarning: LocalizedStringKey = "Move to a brighter area"
        /// Distance coaching, shown while positioning.
        nonisolated(unsafe) static let moveCloser: LocalizedStringKey = "Move a little closer"
        nonisolated(unsafe) static let moveBack: LocalizedStringKey = "Move a little back"

        // Head-rotation ring phase
        nonisolated(unsafe) static let rotateHead: LocalizedStringKey = "Slowly move your head in a circle"
        nonisolated(unsafe) static let keepGoing: LocalizedStringKey = "Keep going — almost there"
        /// Accessibility escape hatch shown during the ring phase (Apple's label).
        nonisolated(unsafe) static let accessibilityOptions: LocalizedStringKey = "Accessibility Options"

        /// Success caption held briefly before the flow advances.
        nonisolated(unsafe) static let allSet: LocalizedStringKey = "All set"
        /// Title on the face-check failure screen (the reason is the subtitle).
        nonisolated(unsafe) static let failTitle: LocalizedStringKey = "Let's try that again"

        /// Terminal failure messages. Plain `String`, not `LocalizedStringKey` —
        /// they're stored as the associated value of `FaceStep.failed(String)` and
        /// rendered with `Text(verbatim:)`.
        ///
        /// Note: liveness/anti-spoof and face-mismatch outcomes are deliberately
        /// **generic** to the end user — revealing *why* a check failed helps an
        /// attacker iterate. The precise result is always available to the
        /// integrator on `IDVFaceMatchResult` / `IDVLivenessOutcome`.
        enum Failure {
            static let unsupportedDevice = "Face scanning needs a device with Face ID (TrueDepth camera)."
            static let faceMismatch = "Make sure your face is well lit and fully inside the circle."
            static let noFaceDetected = "Move somewhere brighter and centre your face in the circle."
            static let multipleFaces = "Make sure you're the only person in view."
            static let generic = "Something went wrong — let's give it another go."
            static let challengeTimeout = "That took a little long. Let's try once more."
            static let sessionTimeout = "That took a little long. Let's try once more."
        }
    }

    /// Pre-liveness coaching tutorial. An auto-advancing, swipeable pager whose
    /// pages are chosen to match the liveness mode; each page animates the action.
    enum Tutorial {
        nonisolated(unsafe) static let title: LocalizedStringKey = "Let's check it's really you"
        nonisolated(unsafe) static let pageFit: LocalizedStringKey = "Fit your face inside the circle"
        nonisolated(unsafe) static let pageRotate: LocalizedStringKey = "Slowly move your head to complete the circle"
        nonisolated(unsafe) static let pageBlinkLeft: LocalizedStringKey = "When asked, blink your left eye"
        nonisolated(unsafe) static let pageBlinkRight: LocalizedStringKey = "When asked, blink your right eye"
        nonisolated(unsafe) static let pageSmile: LocalizedStringKey = "When asked, give a little smile"
        nonisolated(unsafe) static let pageOpenMouth: LocalizedStringKey = "When asked, open your mouth"
        nonisolated(unsafe) static let pageTurnLeft: LocalizedStringKey = "When asked, turn your head left"
        nonisolated(unsafe) static let pageTurnRight: LocalizedStringKey = "When asked, turn your head right"
        nonisolated(unsafe) static let pageHold: LocalizedStringKey = "Hold still and look at the camera"
    }

    enum Challenge {
        nonisolated(unsafe) static let blinkLeft: LocalizedStringKey = "Blink your left eye"
        nonisolated(unsafe) static let blinkRight: LocalizedStringKey = "Blink your right eye"
        nonisolated(unsafe) static let smile: LocalizedStringKey = "Smile"
        nonisolated(unsafe) static let openMouth: LocalizedStringKey = "Open your mouth"
        nonisolated(unsafe) static let turnLeft: LocalizedStringKey = "Turn your head left"
        nonisolated(unsafe) static let turnRight: LocalizedStringKey = "Turn your head right"
    }

    enum Button {
        nonisolated(unsafe) static let start: LocalizedStringKey = "Start"
        nonisolated(unsafe) static let cancel: LocalizedStringKey = "Cancel"
        nonisolated(unsafe) static let scanDocument: LocalizedStringKey = "Scan document"
        nonisolated(unsafe) static let scanChip: LocalizedStringKey = "Scan chip"
        nonisolated(unsafe) static let scanAgain: LocalizedStringKey = "Scan again"
        nonisolated(unsafe) static let tryAgain: LocalizedStringKey = "Try again"
        nonisolated(unsafe) static let proceed: LocalizedStringKey = "Continue"
        nonisolated(unsafe) static let chooseType: LocalizedStringKey = "Choose document type"
        nonisolated(unsafe) static let chooseDifferent: LocalizedStringKey = "Choose a different type"
        nonisolated(unsafe) static let skip: LocalizedStringKey = "Skip"
        nonisolated(unsafe) static let startFaceScan: LocalizedStringKey = "Start face scan"
        nonisolated(unsafe) static let done: LocalizedStringKey = "Done"
    }

    nonisolated(unsafe) static let securedBadge: LocalizedStringKey = "Secured on-device by IDVKit"

    /// Contextual help shown from the top-bar Help button, as an alert.
    enum Help {
        nonisolated(unsafe) static let button: LocalizedStringKey = "Help"
        nonisolated(unsafe) static let ok: LocalizedStringKey = "Got it"
        nonisolated(unsafe) static let nfcTitle: LocalizedStringKey = "Tips for reading the chip"
        nonisolated(unsafe) static let nfcTips: LocalizedStringKey = """
        • Rest the top of your iPhone flat on the passport's photo page.
        • Keep both still until the read finishes.
        • Remove any case — thick or metal cases block the chip.
        • If it won't start, slide the phone slowly around the top half of the cover.
        • Make sure your document has the chip symbol.
        """
        nonisolated(unsafe) static let faceTitle: LocalizedStringKey = "Tips for the face check"
        nonisolated(unsafe) static let faceTips: LocalizedStringKey = """
        • Find even, bright light — face a window.
        • Remove hats, sunglasses or masks.
        • Hold the phone at eye level.
        • Keep your whole face inside the circle.
        • Move slowly and steadily.
        """
    }

    enum DocumentKind {
        nonisolated(unsafe) static let passportTitle: LocalizedStringKey = "Passport"
        nonisolated(unsafe) static let passportSubtitle: LocalizedStringKey = "Booklet with a photo page"
        nonisolated(unsafe) static let idCardTitle: LocalizedStringKey = "ID card"
        nonisolated(unsafe) static let idCardSubtitle: LocalizedStringKey = "National identity card"
        nonisolated(unsafe) static let residencePermitTitle: LocalizedStringKey = "Residence permit"
        nonisolated(unsafe) static let residencePermitSubtitle: LocalizedStringKey = "Residence or work permit"
        nonisolated(unsafe) static let anyTitle: LocalizedStringKey = "Identity document"
        nonisolated(unsafe) static let anySubtitle: LocalizedStringKey = "Any supported ID"

        static let passportNoun = "a passport"
        static let idCardNoun = "an ID card"
        static let residencePermitNoun = "a residence permit"
        static let anyNoun = "an identity document"
    }

    #if DEBUG
        enum Debug {
            nonisolated(unsafe) static let usePhoto: LocalizedStringKey = "Use a photo as reference (testing)"
            nonisolated(unsafe) static let photoSet: LocalizedStringKey = "Reference photo set ✓ — tap to change"
        }
    #endif
}
