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
/// Blend-shape fields use **ARKit's** naming (the front camera is mirrored, so
/// ARKit's `eyeBlinkLeft` is the user's *right* eye — ``VIDLivenessSession``
/// applies that correction). Decoupling from `ARFaceAnchor` keeps the liveness
/// logic unit-testable without a camera and free of an ARKit import.
package struct VIDFaceFrame: Sendable, Equatable {
    /// ARKit `eyeBlinkLeft` (the user's right eye), 0…1.
    package var eyeBlinkLeft: Float
    /// ARKit `eyeBlinkRight` (the user's left eye), 0…1.
    package var eyeBlinkRight: Float
    /// Left mouth-corner smile, 0…1.
    package var smileLeft: Float
    /// Right mouth-corner smile, 0…1.
    package var smileRight: Float
    /// Jaw-open amount, 0…1.
    package var jawOpen: Float
    /// Head yaw in radians (+ = the user's head turned to their right).
    package var yaw: Float
    /// Head pitch in radians.
    package var pitch: Float
    /// Distance from camera in metres.
    package var distance: Float

    package init(
        eyeBlinkLeft: Float = 0, eyeBlinkRight: Float = 0,
        smileLeft: Float = 0, smileRight: Float = 0, jawOpen: Float = 0,
        yaw: Float = 0, pitch: Float = 0, distance: Float = 0.4
    ) {
        self.eyeBlinkLeft = eyeBlinkLeft
        self.eyeBlinkRight = eyeBlinkRight
        self.smileLeft = smileLeft
        self.smileRight = smileRight
        self.jawOpen = jawOpen
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
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
    package static func evaluate(_ challenge: VIDLivenessChallenge, frame: VIDFaceFrame) -> Bool {
        switch challenge {
        // Front camera is mirrored: the user's left eye is ARKit's `eyeBlinkRight`.
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
