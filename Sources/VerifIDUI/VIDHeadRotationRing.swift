//
//  VIDHeadRotationRing.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import SwiftUI

/// A ring of short **radial tick marks** around the face oval for the
/// head-rotation phase, matching Apple's Face ID enrollment: ticks are neutral
/// when unlit and the accent (green) when lit, and they light in the direction the
/// user's nose points as they roll their head. Flat colour, rounded caps, no glow —
/// the restraint is what reads as premium. Purely decorative.
struct VIDHeadRotationRing: View {
    /// One flag per tick, parallel to `VIDHeadRotationTracker.filledSegments`.
    let filled: [Bool]
    /// The face oval's size; the tick ring sits a fixed gap outside it.
    let ovalSize: CGSize
    /// Colour of a lit tick.
    let activeColor: Color
    /// Colour of an unlit tick.
    let idleColor: Color

    var body: some View {
        let count = max(filled.count, 1)
        let radiusX = ovalSize.width / 2 + VIDLayout.Size.ringOvalGap
        let radiusY = ovalSize.height / 2 + VIDLayout.Size.ringOvalGap
        ZStack {
            ForEach(0 ..< count, id: \.self) { index in
                let angle = Double(index) / Double(count) * 2 * .pi
                Capsule()
                    .fill(isFilled(index) ? activeColor : idleColor)
                    .frame(width: VIDLayout.Size.ringTickThickness, height: VIDLayout.Size.ringTickLength)
                    // Uniform, evenly-spaced radial ticks (like Apple's). The
                    // position angle and the tick's rotation use the SAME angle, so
                    // every tick points cleanly outward — no wobble.
                    .rotationEffect(.radians(angle + .pi / 2))
                    .offset(x: radiusX * cos(angle), y: radiusY * sin(angle))
                    .animation(.easeOut(duration: VIDLayout.Duration.ringSegmentFill), value: filled)
            }
        }
        .frame(width: (radiusX + VIDLayout.Size.ringTickLength) * 2,
               height: (radiusY + VIDLayout.Size.ringTickLength) * 2)
        .accessibilityHidden(true)
    }

    private func isFilled(_ index: Int) -> Bool {
        index < filled.count && filled[index]
    }
}
