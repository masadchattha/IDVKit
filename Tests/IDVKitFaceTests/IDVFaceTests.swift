//
//  IDVFaceTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import IDVKitCore
@testable import IDVKitFace
import Testing

struct FaceEmbeddingMathTests {
    @Test func identicalVectorsAreMaximallySimilar() {
        let v: [Float] = [0.2, -0.5, 0.8, 0.1, -0.3]
        #expect(abs(IDVFaceMatcher.cosineSimilarity(v, v) - 1.0) < 1e-5)
    }

    @Test func oppositeVectorsAreMinimallySimilar() {
        let v: [Float] = [1, 2, 3]
        let opposite = v.map { -$0 }
        #expect(abs(IDVFaceMatcher.cosineSimilarity(v, opposite) + 1.0) < 1e-5)
    }

    @Test func orthogonalVectorsAreZero() {
        #expect(abs(IDVFaceMatcher.cosineSimilarity([1, 0], [0, 1])) < 1e-6)
    }

    @Test func mismatchedOrEmptyLengthsAreZero() {
        #expect(IDVFaceMatcher.cosineSimilarity([1, 2, 3], [1, 2]) == 0)
        #expect(IDVFaceMatcher.cosineSimilarity([], []) == 0)
    }

    @Test func l2NormalizeProducesUnitLength() {
        let n = IDVFaceMatcher.l2Normalize([3, 4]) // |v| = 5
        #expect(abs(n[0] - 0.6) < 1e-5)
        #expect(abs(n[1] - 0.8) < 1e-5)
        let magnitude = (n[0] * n[0] + n[1] * n[1]).squareRoot()
        #expect(abs(magnitude - 1.0) < 1e-5)
    }

    @Test func l2NormalizeLeavesZeroVectorUnchanged() {
        #expect(IDVFaceMatcher.l2Normalize([0, 0, 0]) == [0, 0, 0])
    }
}

struct LivenessLogicTests {
    private func session(_ challenges: [IDVLivenessChallenge]) -> IDVLivenessSession {
        IDVLivenessSession(configuration: .init(challenges: .fixed(challenges)))
    }

    @Test func fixedChallengesAreUsedInOrder() {
        let s = session([.smile, .turnLeft])
        #expect(s.challenges == [.smile, .turnLeft])
        #expect(s.currentChallenge == .smile)
        #expect(s.advance() == true)
        #expect(s.currentChallenge == .turnLeft)
        #expect(s.advance() == false)
        #expect(s.currentChallenge == nil)
        #expect(s.completedChallengeNames == ["smile", "turnLeft"])
    }

    @Test func randomChallengesRespectCount() {
        let s = IDVLivenessSession(configuration: .init(challenges: .random(count: 3)))
        #expect(s.challenges.count == 3)
        #expect(Set(s.challenges).count == 3) // non-repeating
    }

    @Test func smileChallengeNeedsBothCorners() {
        #expect(IDVLivenessSession.evaluate(.smile, frame: .init(smileLeft: 0.8, smileRight: 0.8)))
        #expect(!IDVLivenessSession.evaluate(.smile, frame: .init(smileLeft: 0.8, smileRight: 0.1)))
    }

    @Test func openMouthUsesJawOpen() {
        #expect(IDVLivenessSession.evaluate(.openMouth, frame: .init(jawOpen: 0.6)))
        #expect(!IDVLivenessSession.evaluate(.openMouth, frame: .init(jawOpen: 0.2)))
    }

    @Test func blinkChallengesUseTheMirroredEye() {
        // Mirrored selfie preview: "blink your left eye" = the eye on the left of
        // the mirror = ARKit eyeBlinkRight (device-confirmed).
        #expect(IDVLivenessSession.evaluate(.blinkLeft, frame: .init(eyeBlinkRight: 0.9)))
        #expect(!IDVLivenessSession.evaluate(.blinkLeft, frame: .init(eyeBlinkLeft: 0.9)))
        #expect(IDVLivenessSession.evaluate(.blinkRight, frame: .init(eyeBlinkLeft: 0.9)))
        #expect(!IDVLivenessSession.evaluate(.blinkRight, frame: .init(eyeBlinkRight: 0.9)))
    }

    @Test func headTurnDirectionsAreMirrored() {
        // On the mirrored preview, "turn left" reads as −yaw (device-confirmed).
        #expect(IDVLivenessSession.evaluate(.turnLeft, frame: .init(yaw: -0.5)))
        #expect(IDVLivenessSession.evaluate(.turnRight, frame: .init(yaw: 0.5)))
        #expect(!IDVLivenessSession.evaluate(.turnLeft, frame: .init(yaw: 0.5)))
    }

    @Test func microMovementRejectsStaticPhotoAcceptsLiveSway() {
        // A flat photo: identical yaw every frame → zero variance → rejected.
        let still = IDVLivenessSession(configuration: .init(challenges: .fixed([.smile])))
        for _ in 0 ..< 60 {
            still.recordPositioningSample(yaw: 0.10)
        }
        #expect(still.hasPassedMicroMovementCheck == false)

        // A live face: natural sway well above the default 0.002 threshold.
        let live = IDVLivenessSession(configuration: .init(challenges: .fixed([.smile])))
        for i in 0 ..< 60 {
            live.recordPositioningSample(yaw: Float(i % 2) * 0.05)
        }
        #expect(live.hasPassedMicroMovementCheck == true)
    }

    @Test func neutralPoseRequiresStraightFaceAndOpenEyes() {
        #expect(IDVLivenessSession.isNeutralPose(frame: .init(yaw: 0.05, pitch: 0.05)))
        #expect(!IDVLivenessSession.isNeutralPose(frame: .init(eyeBlinkLeft: 0.9)))
        #expect(!IDVLivenessSession.isNeutralPose(frame: .init(yaw: 0.5)))
    }
}

struct LivenessModeTests {
    @Test func headRotationIsTheDefault() {
        #expect(IDVFaceConfiguration().livenessMode == .headRotation)
        #expect(IDVFaceConfiguration().showsTutorial == true)
    }

    @Test func modeCapabilityFlags() {
        #expect(IDVLivenessMode.headRotation.usesHeadRotation)
        #expect(!IDVLivenessMode.headRotation.usesActiveChallenges)
        #expect(IDVLivenessMode.activeChallenges.usesActiveChallenges)
        #expect(!IDVLivenessMode.activeChallenges.usesHeadRotation)
        #expect(IDVLivenessMode.both.usesActiveChallenges && IDVLivenessMode.both.usesHeadRotation)
        #expect(!IDVLivenessMode.passive.usesActiveChallenges && !IDVLivenessMode.passive.usesHeadRotation)
    }
}

struct HeadRotationTrackerTests {
    /// A tracker with smoothing disabled (`alpha: 1`) for deterministic
    /// single-frame assertions.
    private func tracker(segments: Int = 36, cluster: Int = 0, coverage: Float = 0.85) -> IDVHeadRotationTracker {
        IDVHeadRotationTracker(
            segmentCount: segments, deadZone: 0.05, fillMagnitude: 0.15,
            clusterHalfWidth: cluster, requiredCoverage: coverage, smoothingAlpha: 1
        )
    }

    @Test func frontalFramesDoNotLatch() {
        let t = tracker()
        #expect(t.record(directionX: 0.01, directionY: 0) == false) // inside dead zone
        #expect(t.filledCount == 0)
        #expect(!t.isComplete)
    }

    @Test func rotatingFillsTheRing() {
        let t = tracker(segments: 12, cluster: 0, coverage: 1)
        // Sweep the pointing direction a full circle at each tick's centre.
        for step in 0 ..< 12 {
            let angle = (Float(step) + 0.5) / 12 * 2 * .pi
            t.record(directionX: 0.3 * cos(angle), directionY: -0.3 * sin(angle))
        }
        #expect(t.filledCount == 12)
        #expect(t.isComplete)
    }

    @Test func clusterLightsNeighbouringTicks() {
        let t = tracker(segments: 36, cluster: 2, coverage: 1)
        #expect(t.record(directionX: 0.3, directionY: 0) == true)
        #expect(t.filledCount == 5) // centre ± 2
    }

    @Test func latchingKeepsTicksLitAndDedupes() {
        let t = tracker(segments: 12, cluster: 0)
        #expect(t.record(directionX: 0.3, directionY: 0) == true)
        #expect(t.record(directionX: 0.3, directionY: 0) == false) // already lit
        #expect(t.filledCount == 1)
    }

    @Test func completesAtQuorumNotFullSweep() {
        let t = tracker(segments: 10, cluster: 0, coverage: 0.7)
        for step in 0 ..< 7 {
            let angle = (Float(step) + 0.5) / 10 * 2 * .pi
            t.record(directionX: 0.3 * cos(angle), directionY: -0.3 * sin(angle))
        }
        #expect(t.filledCount == 7)
        #expect(t.isComplete) // 0.7 coverage reached without the last 3
    }

    @Test func smoothingDampsASingleFrame() {
        // Default smoothing (alpha 0.3): one frame of a large direction is damped
        // below the fill threshold (0.3 × 0.3 = 0.09 < 0.20), so it can't latch
        // instantly — this is what stops jitter from flickering ticks.
        let t = IDVHeadRotationTracker()
        #expect(t.record(directionX: 0.3, directionY: 0) == false)
    }

    @Test func resetClearsProgress() {
        let t = tracker(segments: 12, cluster: 0)
        t.record(directionX: 0.3, directionY: 0)
        #expect(t.filledCount > 0)
        t.reset()
        #expect(t.filledCount == 0)
    }
}
