//
//  IDVLayout.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import CoreGraphics
import Foundation

/// Fixed layout metrics for the drop-in UI, so no raw numbers appear in view
/// bodies. This holds only values that are **not** part of ``IDVTheme`` — the
/// themeable tokens (colors, fonts, `screenPadding`, `cornerRadius`,
/// `buttonCornerRadius`) stay on the theme so integrators can override them.
enum IDVLayout {
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
        /// Success checkmark on the capture success state. 60
        static let success: CGFloat = 60
        /// Tutorial guidance-point icon. 24
        static let tutorialPoint: CGFloat = 24
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

        // Chip glyph (IDVChipSymbol)
        static let chipGlyphWidth: CGFloat = 34
        /// 46
        static let chipGlyphHeight: CGFloat = 46
        /// 14
        static let chipGlyphCircle: CGFloat = 14
        /// 16
        static let chipGlyphBarWidth: CGFloat = 16
        /// 2.5
        static let chipGlyphBarHeight: CGFloat = 2.5

        // NFC tap animation (IDVNFCTapAnimation)
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

        // Face capture circle (IDVFaceCaptureView) — Apple Face-ID proportions
        /// Circle diameter as a fraction of the screen width. 0.68
        static let captureCircleFactor: CGFloat = 0.68
        /// Cap on the capture circle's diameter. 300
        static let ovalMaxWidth: CGFloat = 300
        /// Vertical center of the circle, as a fraction of the screen height. 0.4
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

        // Head-rotation ring (IDVHeadRotationRing) — radial ticks around the oval,
        // Apple-Face-ID style.
        /// Gap in points between the oval's edge and the tick ring. 18
        static let ringOvalGap: CGFloat = 18
        /// Radial tick length. 13
        static let ringTickLength: CGFloat = 13
        /// Radial tick thickness. 3.5
        static let ringTickThickness: CGFloat = 3.5
        /// Success checkmark circle behind the glyph on the success state. 108
        static let successBadge: CGFloat = 108

        // Pre-liveness tutorial (IDVFaceTutorialView) — Apple-Face-ID-style pager
        /// Overall tutorial ring+face frame. 200
        static let tutorialDemo: CGFloat = 200
        /// Smiley-face circle diameter inside the tutorial ring. 124
        static let tutorialCircle: CGFloat = 124
        /// Height of the swipeable tutorial pager (face + caption). 280
        static let tutorialPagerHeight: CGFloat = 280
        /// Custom pager dot diameter. 8
        static let pagerDot: CGFloat = 8

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
        /// Head-rotation ring segment. 6
        static let ringSegment: CGFloat = 6
    }

    /// Head-rotation ring geometry.
    enum Ring {
        /// Angular gap between adjacent segments, in degrees. 5
        static let segmentGapDegrees: Double = 5
    }

    /// Soft "Siri"-style glow haloing the capture circle.
    enum Glow {
        /// Added to the circle diameter so the halo sits just outside it. 26
        static let inset: CGFloat = 26
        /// Blurred gradient ring width. 24
        static let lineWidth: CGFloat = 24
        /// Blur radius softening the ring into a glow. 20
        static let blur: CGFloat = 20
        /// Overall glow opacity. 0.6
        static let opacity: CGFloat = 0.6
        /// Seconds for one full rotation of the gradient. 6
        static let rotationPeriod: Double = 6
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
        /// Unfilled head-rotation ring tick in the tutorial illustration. 0.35
        static let ringInactive: CGFloat = 0.35
        /// Scrim behind the capture success overlay. 0.5
        static let successScrim: CGFloat = 0.5
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
        /// Time a neutral pose must hold before it's accepted. 2.0
        static let neutralPoseSettle: TimeInterval = 2.0
        /// Fallback capture if the pose never settles perfectly — long enough that
        /// the user can calmly settle and look at the camera after the ring fills. 5.0
        static let neutralPoseFallback: TimeInterval = 5.0
        /// Delay between the capture "flash" cue and the actual capture. 0.3
        static let captureFlashDelay: TimeInterval = 0.3
        /// Pause on the success pulse before advancing to the next challenge. 0.5
        static let challengeTransition: TimeInterval = 0.5
        /// Head-rotation ring segment fill animation. 0.2
        static let ringSegmentFill: Double = 0.2
        /// Pause on the fully-filled green ring so the user sees it complete before
        /// the flow moves on to the neutral capture. 2.5
        static let ringCompletePause: TimeInterval = 2.5
        /// Hold on the success checkmark before the flow advances. 0.7
        static let successDwell: TimeInterval = 0.7
        /// Fallback for the head-rotation phase if it's never completed (auto-
        /// advances to capture so the user is never stuck). 25
        static let headRotationTimeout: TimeInterval = 25
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
        /// Design-preview placeholder glyph size, as a fraction of the circle. 0.4
        static let placeholderGlyph: CGFloat = 0.4
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

    /// Face-distance coaching thresholds, in raw ARKit metres (device-tuned:
    /// `ARFaceAnchor` translation z). Outside this band the user is nudged.
    enum Distance {
        /// Beyond this, show "move closer". 0.55 m
        static let tooFar: Float = 0.55
        /// Nearer than this, show "move back". 0.22 m
        static let tooClose: Float = 0.22
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
