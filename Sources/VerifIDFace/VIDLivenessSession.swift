//
//  VIDLivenessSession.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation
import VerifIDCore

/// One frame of face-tracking data, reduced to the plain values liveness needs.
///
/// Blend-shape fields use ARKit's naming, which per Apple is **relative to the
/// face itself** — `eyeBlinkLeft` is the user's *own* left eye, `eyeBlinkRight`
/// their own right eye (see `ARFaceAnchor.BlendShapeLocation`). No mirror swap is
/// applied. Decoupling from `ARFaceAnchor` keeps the liveness logic
/// unit-testable without a camera and free of an ARKit import.
package struct VIDFaceFrame: Sendable, Equatable {
    /// Blink amount of the user's own left eye (ARKit `eyeBlinkLeft`), 0…1.
    package var eyeBlinkLeft: Float
    /// Blink amount of the user's own right eye (ARKit `eyeBlinkRight`), 0…1.
    package var eyeBlinkRight: Float
    /// Left mouth-corner smile, 0…1.
    package var smileLeft: Float
    /// Right mouth-corner smile, 0…1.
    package var smileRight: Float
    /// Jaw-open amount, 0…1.
    package var jawOpen: Float
    /// Head yaw in radians. Per ARKit's documented axes (+x = the face's own
    /// left), **+ = the user turned their head to their own left**.
    package var yaw: Float
    /// Head pitch in radians (+ = looking up).
    package var pitch: Float
    /// Distance from camera in metres.
    package var distance: Float
    /// Screen-space X of where the nose points, **camera-relative and mirrored**
    /// to match the selfie preview (+ = the user's head turned toward the side that
    /// appears right on screen). ~0 when frontal, grows as the head turns. Drives
    /// the head-rotation ring.
    package var directionX: Float
    /// Screen-space Y of where the nose points, camera-relative (+ = looking up).
    package var directionY: Float

    package init(
        eyeBlinkLeft: Float = 0, eyeBlinkRight: Float = 0,
        smileLeft: Float = 0, smileRight: Float = 0, jawOpen: Float = 0,
        yaw: Float = 0, pitch: Float = 0, distance: Float = 0.4,
        directionX: Float = 0, directionY: Float = 0
    ) {
        self.eyeBlinkLeft = eyeBlinkLeft
        self.eyeBlinkRight = eyeBlinkRight
        self.smileLeft = smileLeft
        self.smileRight = smileRight
        self.jawOpen = jawOpen
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
        self.directionX = directionX
        self.directionY = directionY
    }
}

/// Active liveness detection driven by face-tracking frames: a sequence of
/// blend-shape challenges (blink, smile, open mouth, head turn) plus a
/// micro-movement anti-spoofing gate (natural head sway that a photo or screen
/// lacks). The UI layer feeds it ``VIDFaceFrame`` values from ARKit; this type
/// holds no camera or ARKit dependency, so its logic is fully unit-testable.
package final class VIDLivenessSession {
    package let configuration: VIDFaceConfiguration

    /// The challenges the user must complete, in order.
    package private(set) var challenges: [VIDLivenessChallenge]
    package private(set) var currentChallengeIndex = 0

    /// The "rotate to fill the ring" phase tracker (used when
    /// ``VIDFaceConfiguration/livenessMode`` includes head rotation).
    package let headRotation = VIDHeadRotationTracker()

    private var yawSamples: [Float] = []

    package init(configuration: VIDFaceConfiguration = .init()) {
        self.configuration = configuration
        challenges = Self.makeChallenges(configuration.challenges)
    }

    // MARK: Challenge sequence

    package var currentChallenge: VIDLivenessChallenge? {
        currentChallengeIndex < challenges.count ? challenges[currentChallengeIndex] : nil
    }

    /// Advances to the next challenge; returns `false` when all are complete.
    @discardableResult
    package func advance() -> Bool {
        currentChallengeIndex += 1
        return currentChallengeIndex < challenges.count
    }

    /// The raw values of the challenges completed so far — for ``VIDLivenessOutcome``.
    package var completedChallengeNames: [String] {
        challenges.prefix(currentChallengeIndex).map(\.rawValue)
    }

    /// Resets for a new attempt, re-picking challenges.
    package func reset() {
        challenges = Self.makeChallenges(configuration.challenges)
        currentChallengeIndex = 0
        yawSamples = []
        headRotation.reset()
    }

    private static func makeChallenges(_ selection: VIDFaceConfiguration.ChallengeSelection) -> [VIDLivenessChallenge] {
        switch selection {
        case let .random(count): Array(VIDLivenessChallenge.allCases.shuffled().prefix(max(1, count)))
        case let .fixed(list): list.isEmpty ? [.blinkLeft] : list
        }
    }

    // MARK: Micro-movement anti-spoofing

    /// Frames needed for the micro-movement check (~0.5s at 60fps).
    private static let microMovementFrameCount = 30

    /// Records a yaw sample while the user is positioning. A live person's head
    /// micro-sways even when "holding still"; a flat photo has near-zero variance.
    package func recordPositioningSample(yaw: Float) {
        yawSamples.append(yaw)
    }

    package var positioningSampleCount: Int {
        yawSamples.count
    }

    /// Whether enough natural head micro-sway has been seen to accept a live face.
    package var hasPassedMicroMovementCheck: Bool {
        guard yawSamples.count >= Self.microMovementFrameCount else { return false }
        let recent = Array(yawSamples.suffix(Self.microMovementFrameCount))
        return Self.standardDeviation(recent) >= configuration.microMovementThreshold
    }

    // MARK: Evaluation

    private enum Threshold {
        static let blink: Float = 0.7
        static let smile: Float = 0.5
        static let jawOpen: Float = 0.4
        static let turnAngle: Float = .pi / 12 // 15°
    }

    /// Whether the given frame satisfies a challenge.
    ///
    /// The front-camera preview is **mirrored** (selfie mirror), so the prompt's
    /// "left/right" is what the user sees on the mirrored screen — which is the
    /// opposite anatomical side. Device testing confirms: "blink your left eye"
    /// means the eye on the left of the mirror = ARKit `eyeBlinkRight`, and "turn
    /// left" (on-screen) is −yaw. Both are swapped from the raw ARKit convention to
    /// match what the user actually perceives.
    package static func evaluate(_ challenge: VIDLivenessChallenge, frame: VIDFaceFrame) -> Bool {
        switch challenge {
        case .blinkLeft: frame.eyeBlinkRight > Threshold.blink
        case .blinkRight: frame.eyeBlinkLeft > Threshold.blink
        case .smile: frame.smileLeft > Threshold.smile && frame.smileRight > Threshold.smile
        case .openMouth: frame.jawOpen > Threshold.jawOpen
        case .turnLeft: frame.yaw < -Threshold.turnAngle
        case .turnRight: frame.yaw > Threshold.turnAngle
        }
    }

    /// Whether the face is straight and eyes-open — a good neutral pose to capture
    /// the still used for face matching.
    package static func isNeutralPose(frame: VIDFaceFrame) -> Bool {
        abs(frame.yaw) < .pi / 12
            && abs(frame.pitch) < .pi / 12
            && frame.eyeBlinkLeft < 0.4
            && frame.eyeBlinkRight < 0.4
    }

    private static func standardDeviation(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let count = Float(values.count)
        let mean = values.reduce(0, +) / count
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count
        return sqrt(variance)
    }
}
