//
//  VIDHeadRotationTracker.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation

/// Tracks the "rotate your head to fill the ring" liveness phase, matching Apple's
/// Face ID enrollment interaction. The ring is a set of radial **tick** segments;
/// as the user rolls their head, the tick(s) in the direction their nose points
/// light up and **stay lit** (latched). Completing a quorum proves genuine 3-D head
/// motion — a flat photo or screen replay can't fill the ring.
///
/// It's fed a **camera-relative, mirror-corrected screen direction** (see
/// ``VIDFaceFrame/directionX`` / ``directionY``) rather than raw Euler angles,
/// which per Apple's guidance avoids gimbal/sign/mirroring bugs. To feel alive it
/// (1) low-pass smooths the noisy pose, (2) ignores a centre dead-zone so a frontal
/// face doesn't flicker ticks, and (3) lights a small **cluster** of ticks around
/// the pointing direction so a smooth roll paints a continuous band. Pure logic, no
/// ARKit — fully unit-testable.
package final class VIDHeadRotationTracker {
    /// How many radial ticks the ring has. The capture UI draws exactly this many,
    /// so this is the single source of truth for both.
    package let segmentCount: Int
    /// Below this smoothed magnitude the head is treated as frontal (dead-zone).
    package let deadZone: Float
    /// At/above this smoothed magnitude a tick latches.
    package let fillMagnitude: Float
    /// Ticks lit on each side of the pointing direction (a small arc, not one tick).
    package let clusterHalfWidth: Int
    /// Fraction of ticks that must latch to pass (Apple doesn't demand a perfect
    /// sweep either).
    package let requiredCoverage: Float

    private var filled: [Bool]
    private var smoothedX: Float = 0
    private var smoothedY: Float = 0
    private let smoothingAlpha: Float

    /// - Parameters:
    ///   - segmentCount: Ring ticks (default 36 ≈ 10° each).
    ///   - deadZone: Centre dead-zone magnitude (default 0.10).
    ///   - fillMagnitude: Latch threshold magnitude (default 0.20).
    ///   - clusterHalfWidth: Ticks lit either side of centre (default 2 → a 5-tick arc).
    ///   - requiredCoverage: Pass fraction 0…1 (default 0.85).
    ///   - smoothingAlpha: Low-pass factor 0…1; 1 disables smoothing (default 0.3).
    package init(
        segmentCount: Int = 60,
        deadZone: Float = 0.10,
        fillMagnitude: Float = 0.20,
        clusterHalfWidth: Int = 4,
        requiredCoverage: Float = 0.85,
        smoothingAlpha: Float = 0.3
    ) {
        self.segmentCount = max(8, segmentCount)
        self.deadZone = deadZone
        self.fillMagnitude = fillMagnitude
        self.clusterHalfWidth = max(0, clusterHalfWidth)
        self.requiredCoverage = min(max(requiredCoverage, 0), 1)
        self.smoothingAlpha = min(max(smoothingAlpha, 0), 1)
        filled = Array(repeating: false, count: self.segmentCount)
    }

    /// Which ticks are currently lit (parallel to the drawn ticks).
    package var filledSegments: [Bool] {
        filled
    }

    /// Number of ticks lit so far.
    package var filledCount: Int {
        var count = 0
        for isLit in filled where isLit {
            count += 1
        }
        return count
    }

    /// Fill fraction, 0…1.
    package var progress: Float {
        Float(filledCount) / Float(segmentCount)
    }

    /// Whether enough of the ring is covered to pass.
    package var isComplete: Bool {
        progress >= requiredCoverage
    }

    /// Feeds one frame's mirror-corrected head direction in. Returns `true` if this
    /// frame latched at least one new tick (for a per-arc haptic tick).
    ///
    /// - Parameters:
    ///   - directionX: Screen-space X of where the nose points (mirror-corrected).
    ///   - directionY: Screen-space Y of where the nose points (+ = up).
    @discardableResult
    package func record(directionX: Float, directionY: Float) -> Bool {
        // Low-pass filter — ARKit face pose is noisy.
        smoothedX = smoothedX * (1 - smoothingAlpha) + directionX * smoothingAlpha
        smoothedY = smoothedY * (1 - smoothingAlpha) + directionY * smoothingAlpha

        let magnitude = (smoothedX * smoothedX + smoothedY * smoothedY).squareRoot()
        guard magnitude >= max(deadZone, fillMagnitude) else { return false }

        let center = Self.segment(x: smoothedX, y: smoothedY, count: segmentCount)
        var latchedNew = false
        for offset in -clusterHalfWidth ... clusterHalfWidth {
            let index = ((center + offset) % segmentCount + segmentCount) % segmentCount
            if !filled[index] {
                filled[index] = true
                latchedNew = true
            }
        }
        return latchedNew
    }

    /// Clears all progress (and smoothing state) for a fresh attempt.
    package func reset() {
        filled = Array(repeating: false, count: segmentCount)
        smoothedX = 0
        smoothedY = 0
    }

    /// Maps a screen-space head direction to a ring tick index. Angle 0 (nose points
    /// screen-right) is tick 0; indices advance counter-clockwise. `+y` is up, so it
    /// negates y to match a top-is-up ring where tick indices go clockwise on screen.
    static func segment(x: Float, y: Float, count: Int) -> Int {
        var angle = atan2(-y, x) // screen y grows downward; negate so +y = up = top
        if angle < 0 {
            angle += 2 * .pi
        }
        let index = Int(angle / (2 * .pi) * Float(count))
        return min(max(index, 0), count - 1)
    }
}
