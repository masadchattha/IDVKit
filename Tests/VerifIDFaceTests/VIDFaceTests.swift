//
//  VIDFaceTests.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Testing
import VerifIDCore
@testable import VerifIDFace

struct FaceEmbeddingMathTests {
    @Test func identicalVectorsAreMaximallySimilar() {
        let v: [Float] = [0.2, -0.5, 0.8, 0.1, -0.3]
        #expect(abs(VIDFaceMatcher.cosineSimilarity(v, v) - 1.0) < 1e-5)
    }

    @Test func oppositeVectorsAreMinimallySimilar() {
        let v: [Float] = [1, 2, 3]
        let opposite = v.map { -$0 }
        #expect(abs(VIDFaceMatcher.cosineSimilarity(v, opposite) + 1.0) < 1e-5)
    }

    @Test func orthogonalVectorsAreZero() {
        #expect(abs(VIDFaceMatcher.cosineSimilarity([1, 0], [0, 1])) < 1e-6)
    }

    @Test func mismatchedOrEmptyLengthsAreZero() {
        #expect(VIDFaceMatcher.cosineSimilarity([1, 2, 3], [1, 2]) == 0)
        #expect(VIDFaceMatcher.cosineSimilarity([], []) == 0)
    }

    @Test func l2NormalizeProducesUnitLength() {
        let n = VIDFaceMatcher.l2Normalize([3, 4]) // |v| = 5
        #expect(abs(n[0] - 0.6) < 1e-5)
        #expect(abs(n[1] - 0.8) < 1e-5)
        let magnitude = (n[0] * n[0] + n[1] * n[1]).squareRoot()
        #expect(abs(magnitude - 1.0) < 1e-5)
    }

    @Test func l2NormalizeLeavesZeroVectorUnchanged() {
        #expect(VIDFaceMatcher.l2Normalize([0, 0, 0]) == [0, 0, 0])
    }
}

struct LivenessLogicTests {
    private func session(_ challenges: [VIDLivenessChallenge]) -> VIDLivenessSession {
        VIDLivenessSession(configuration: .init(challenges: .fixed(challenges)))
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
        let s = VIDLivenessSession(configuration: .init(challenges: .random(count: 3)))
        #expect(s.challenges.count == 3)
        #expect(Set(s.challenges).count == 3) // non-repeating
    }

    @Test func smileChallengeNeedsBothCorners() {
        #expect(VIDLivenessSession.evaluate(.smile, frame: .init(smileLeft: 0.8, smileRight: 0.8)))
        #expect(!VIDLivenessSession.evaluate(.smile, frame: .init(smileLeft: 0.8, smileRight: 0.1)))
    }

    @Test func openMouthUsesJawOpen() {
        #expect(VIDLivenessSession.evaluate(.openMouth, frame: .init(jawOpen: 0.6)))
        #expect(!VIDLivenessSession.evaluate(.openMouth, frame: .init(jawOpen: 0.2)))
    }

    @Test func blinkLeftMapsToMirroredEye() {
        // The user's left eye is ARKit's eyeBlinkRight (mirrored front camera).
        #expect(VIDLivenessSession.evaluate(.blinkLeft, frame: .init(eyeBlinkRight: 0.9)))
        #expect(!VIDLivenessSession.evaluate(.blinkLeft, frame: .init(eyeBlinkLeft: 0.9)))
    }

    @Test func headTurnDirectionsAreSigned() {
        #expect(VIDLivenessSession.evaluate(.turnRight, frame: .init(yaw: 0.5)))
        #expect(VIDLivenessSession.evaluate(.turnLeft, frame: .init(yaw: -0.5)))
        #expect(!VIDLivenessSession.evaluate(.turnRight, frame: .init(yaw: -0.5)))
    }

    @Test func microMovementRejectsStaticPhotoAcceptsLiveSway() {
        // A flat photo: identical yaw every frame → zero variance → rejected.
        let still = VIDLivenessSession(configuration: .init(challenges: .fixed([.smile])))
        for _ in 0 ..< 60 {
            still.recordPositioningSample(yaw: 0.10)
        }
        #expect(still.hasPassedMicroMovementCheck == false)

        // A live face: natural sway well above the default 0.002 threshold.
        let live = VIDLivenessSession(configuration: .init(challenges: .fixed([.smile])))
        for i in 0 ..< 60 {
            live.recordPositioningSample(yaw: Float(i % 2) * 0.05)
        }
        #expect(live.hasPassedMicroMovementCheck == true)
    }

    @Test func neutralPoseRequiresStraightFaceAndOpenEyes() {
        #expect(VIDLivenessSession.isNeutralPose(frame: .init(yaw: 0.05, pitch: 0.05)))
        #expect(!VIDLivenessSession.isNeutralPose(frame: .init(eyeBlinkLeft: 0.9)))
        #expect(!VIDLivenessSession.isNeutralPose(frame: .init(yaw: 0.5)))
    }
}
