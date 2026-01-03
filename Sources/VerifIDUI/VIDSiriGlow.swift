//
//  VIDSiriGlow.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import SwiftUI

/// A soft, slowly rotating multi-colour halo around the capture circle — a
/// Siri-like glow that makes the live camera feel alive without competing with the
/// green progress ticks. A blurred angular-gradient stroke; freezes under Reduce
/// Motion.
struct VIDSiriGlow: View {
    /// Diameter of the glow ring (usually the camera circle plus a small inset).
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let angle = reduceMotion ? 0 : Self.rotation(at: context.date)
            Circle()
                .strokeBorder(
                    AngularGradient(colors: VIDColor.glowPalette, center: .center),
                    lineWidth: VIDLayout.Glow.lineWidth
                )
                .frame(width: diameter, height: diameter)
                .blur(radius: VIDLayout.Glow.blur)
                .rotationEffect(.degrees(angle))
                .opacity(VIDLayout.Glow.opacity)
        }
        .accessibilityHidden(true)
    }

    static func rotation(at date: Date) -> Double {
        let period = VIDLayout.Glow.rotationPeriod
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * 360
    }
}
