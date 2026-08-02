//
//  IDVSiriGlow.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import SwiftUI

/// A soft, slowly rotating multi-colour halo around the capture circle — a
/// Siri-like glow that makes the live camera feel alive without competing with the
/// green progress ticks. A blurred angular-gradient stroke; freezes under Reduce
/// Motion.
struct IDVSiriGlow: View {
    /// Diameter of the glow ring (usually the camera circle plus a small inset).
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let angle = reduceMotion ? 0 : Self.rotation(at: context.date)
            Circle()
                .strokeBorder(
                    AngularGradient(colors: IDVColor.glowPalette, center: .center),
                    lineWidth: IDVLayout.Glow.lineWidth
                )
                .frame(width: diameter, height: diameter)
                .blur(radius: IDVLayout.Glow.blur)
                .rotationEffect(.degrees(angle))
                .opacity(IDVLayout.Glow.opacity)
        }
        .accessibilityHidden(true)
    }

    static func rotation(at date: Date) -> Double {
        let period = IDVLayout.Glow.rotationPeriod
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * 360
    }
}
