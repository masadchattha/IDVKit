//
//  VIDLayout.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import CoreGraphics
import Foundation

/// Fixed layout metrics for the drop-in UI, so no raw numbers appear in view
/// bodies. This holds only values that are **not** part of ``VIDTheme`` — the
/// themeable tokens (colors, fonts, `screenPadding`, `cornerRadius`,
/// `buttonCornerRadius`) stay on the theme so integrators can override them.
enum VIDLayout {
    /// Spacing not driven by the theme's `screenPadding`.
    enum Spacing {
        /// 2
        static let micro: CGFloat = 2
        /// 4
        static let tiny: CGFloat = 4
        /// 8
        static let small: CGFloat = 8
        /// 10
        static let title: CGFloat = 10
        /// 12
        static let medium: CGFloat = 12
        /// 14
        static let row: CGFloat = 14
        /// 16
        static let large: CGFloat = 16
        /// 22
        static let heroPadding: CGFloat = 22
        /// Extra bottom clearance under the liveness HUD, beyond the safe area. 28
        static let hudBottomExtra: CGFloat = 28
    }

    /// SF Symbol / glyph point sizes.
    enum IconSize {
        /// 26
        static let row: CGFloat = 26
        /// 52
        static let hero: CGFloat = 52
        /// 56
        static let warning: CGFloat = 56
        /// Liveness challenge glyph (e.g. the eye/smile icon above the prompt). 40
        static let challenge: CGFloat = 40
    }

    /// Fixed element dimensions.
    enum Size {
        /// Hero illustration frame.
        static let illustrationMaxWidth: CGFloat = 236
        /// 184
        static let illustrationMaxHeight: CGFloat = 184
        /// Tinted circle behind a hero symbol. 128
        static let heroCircle: CGFloat = 128
        /// Host logo on the intro screen. 72
        static let logo: CGFloat = 72
        /// Document-row icon slot. 40
        static let rowIconSlot: CGFloat = 40
        /// Face portrait thumbnail on the face-intro screen.
        static let facePortraitWidth: CGFloat = 116
        /// 145
        static let facePortraitHeight: CGFloat = 145

        // Chip glyph (VIDChipSymbol)
        static let chipGlyphWidth: CGFloat = 34
        /// 46
        static let chipGlyphHeight: CGFloat = 46
        /// 14
        static let chipGlyphCircle: CGFloat = 14
        /// 16
        static let chipGlyphBarWidth: CGFloat = 16
        /// 2.5
        static let chipGlyphBarHeight: CGFloat = 2.5

        // NFC tap animation (VIDNFCTapAnimation)
        static let nfcFrame: CGFloat = 190
        static let nfcDocWidth: CGFloat = 150
        static let nfcDocHeight: CGFloat = 96
        static let nfcDocChipWidth: CGFloat = 22
        static let nfcDocChipHeight: CGFloat = 16
        static let nfcDocOffsetY: CGFloat = 42
        static let nfcPhoneWidth: CGFloat = 70
        static let nfcPhoneHeight: CGFloat = 114
        static let nfcPhoneOffsetY: CGFloat = -8
        static let nfcScreenWidth: CGFloat = 56
        static let nfcScreenHeight: CGFloat = 98
        static let nfcWaveWidth: CGFloat = 82
        static let nfcWaveHeight: CGFloat = 46
        static let nfcWaveOffsetY: CGFloat = -72

        // Primary/secondary action buttons
        /// Minimum tappable height for the flow's full-width buttons. 52
        static let buttonHeight: CGFloat = 52

        // Face capture oval (VIDFaceCaptureView)
        /// Horizontal inset subtracted from the screen width before capping. 80
        static let ovalHorizontalInset: CGFloat = 80
        /// Cap on the oval's width. 300
        static let ovalMaxWidth: CGFloat = 300
        /// Oval height ÷ width. 1.3
        static let ovalAspectRatio: CGFloat = 1.3
        /// Vertical center of the oval, as a fraction of the screen height. 0.4
        static let ovalVerticalPositionFactor: CGFloat = 0.4

        // Liveness challenge HUD
        /// Fixed height of the icon slot above the instruction text, so the text
        /// never jumps when the icon appears/disappears. 46
        static let challengeIconSlotHeight: CGFloat = 46
        /// Filled capsule width for a completed challenge step. 22
        static let challengeCapsuleActiveWidth: CGFloat = 22
        /// Capsule width for a pending challenge step. 14
        static let challengeCapsuleInactiveWidth: CGFloat = 14
        /// Capsule height for the challenge-progress dots. 5
        static let challengeCapsuleHeight: CGFloat = 5

        // Face-match result thumbnails
        /// Document portrait shown on the result screen. 96
        static let resultPhotoWidth: CGFloat = 96
        /// 120
        static let resultPhotoHeight: CGFloat = 120
        /// Side-by-side reference/live thumbnail on the face-match badge. 56
        static let matchThumbWidth: CGFloat = 56
        /// 70
        static let matchThumbHeight: CGFloat = 70
    }

    /// Corner radii not driven by the theme (added to `theme.cornerRadius`).
    enum Radius {
        /// Extra radius over the theme's for hero panels. 8
        static let heroPanelExtra: CGFloat = 8
        /// Small inner radius (glyphs, chips). 3–5
        static let chip: CGFloat = 3
        static let phone: CGFloat = 15
        static let phoneScreen: CGFloat = 10
        static let glyph: CGFloat = 5
        static let doc: CGFloat = 12
        /// Face-match thumbnail corner radius. 8
        static let matchThumb: CGFloat = 8
    }

    /// Stroke widths.
    enum Stroke {
        /// 2
        static let regular: CGFloat = 2
        /// Hairline border. 1 (used at low opacity)
        static let hairline: CGFloat = 1
        /// NFC wave. 4.5
        static let wave: CGFloat = 4.5
        /// Face-oval capture guide. 4
        static let ovalGuide: CGFloat = 4
    }

    /// Opacity stops.
    enum Opacity {
        /// 0.12
        static let tint: CGFloat = 0.12
        /// 0.3
        static let subtle: CGFloat = 0.3
        /// 0.7
        static let poweredBy: CGFloat = 0.7
        /// 0.92
        static let phoneScreen: CGFloat = 0.92
        /// NFC wave at full visibility, before it fades out. 0.9
        static let waveVisible: CGFloat = 0.9
        /// A chrome icon (e.g. a close button) over a dark camera background. 0.9
        static let chromeIcon: CGFloat = 0.9
        /// Idle face-oval guide. 0.4
        static let ovalIdle: CGFloat = 0.4
        /// Scrim behind the "Verifying…" overlay. 0.82
        static let processingScrim: CGFloat = 0.82
        /// Scrim behind the liveness failure overlay. 0.88
        static let failureScrim: CGFloat = 0.88
        /// Drop shadow behind the "multiple faces" warning banner. 0.25
        static let bannerShadow: CGFloat = 0.25
        /// Muted secondary text on a dark background (e.g. the failure Cancel). 0.8
        static let mutedOnDark: CGFloat = 0.8
    }

    /// Animation timing.
    enum Duration {
        /// Seconds for one NFC wave pulse. 1.8
        static let wavePulse: Double = 1.8
        /// Stagger between the three waves. 0.5
        static let waveStagger: Double = 0.5

        // Face-oval guide
        /// Success pulse scale-up. 0.25
        static let ovalPulse: Double = 0.25
        /// Oval color/stroke transition between states. 0.3
        static let ovalStateChange: Double = 0.3

        // Liveness HUD
        /// Warning-banner show/hide crossfade. 0.2
        static let bannerToggle: Double = 0.2
        /// Challenge-timeout progress bar tick. 0.05
        static let timerTick: Double = 0.05
        /// Grace period to read a challenge prompt before it's evaluated. 1.5
        static let challengeGrace: TimeInterval = 1.5
        /// Anti-spoof sample window before the first challenge starts. 2.5
        static let positioningTimeout: TimeInterval = 2.5
        /// Time a neutral pose must hold before it's accepted. 1.5
        static let neutralPoseSettle: TimeInterval = 1.5
        /// Fallback capture if the pose never settles perfectly. 3.0
        static let neutralPoseFallback: TimeInterval = 3.0
        /// Delay between the capture "flash" cue and the actual capture. 0.3
        static let captureFlashDelay: TimeInterval = 0.3
        /// Pause on the success pulse before advancing to the next challenge. 0.5
        static let challengeTransition: TimeInterval = 0.5
    }

    /// Unitless scale factors.
    enum Scale {
        /// Success pulse on the face oval. 1.04
        static let ovalPulse: CGFloat = 1.04
        /// NFC wave arc, smallest state. 0.5
        static let waveMin: CGFloat = 0.5
        /// NFC wave arc, largest state before fading out. 1.5
        static let waveMax: CGFloat = 1.5
        /// Extra padding factor applied to a document row's default padding. 0.75
        static let rowPaddingFactor: CGFloat = 0.75
    }

    /// Spring animation parameters.
    enum Spring {
        /// Response for the challenge icon's scale/opacity transition. 0.35
        static let challengeIconResponse: Double = 0.35
        /// Damping fraction for the challenge icon's transition. 0.7
        static let challengeIconDamping: Double = 0.7
    }

    /// Drop shadow parameters.
    enum Shadow {
        /// Radius behind the "multiple faces" warning banner. 6
        static let bannerRadius: CGFloat = 6
        /// Vertical offset behind the warning banner. 2
        static let bannerY: CGFloat = 2
    }

    /// Ambient-light thresholds driving the low-light banner (raw
    /// `ARLightEstimate.ambientIntensity` units).
    enum Light {
        /// Below this, the low-light banner shows. 200
        static let low: CGFloat = 200
        /// Above this, the low-light banner hides. 350
        static let normal: CGFloat = 350
        /// Sample the light estimate every N camera frames. 30
        static let sampleFrameInterval: Int = 30
    }

    /// ARKit face-tracking session limits.
    enum FaceTracking {
        /// Tracked faces (so a second face can be detected and rejected). 2
        static let maxTrackedFaces: Int = 2
    }

    /// Fixed background tints (theme-independent — used behind hero art so it
    /// reads on both light and dark).
    enum Fill {
        /// Soft panel behind hero illustrations. #F2F2FF-ish
        static let heroPanel = (red: 0.949, green: 0.949, blue: 1.0)
        /// Navy document in the NFC animation.
        static let navy = (red: 0.106, green: 0.145, blue: 0.349)
    }

    /// NFC wave arc angles (degrees).
    enum Arc {
        static let start: Double = 200
        static let end: Double = 340
    }
}
