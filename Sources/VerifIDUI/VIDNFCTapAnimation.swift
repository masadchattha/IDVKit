//
//  VIDNFCTapAnimation.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import SwiftUI

/// A dependency-free animated coach for the NFC step: a phone resting on the top
/// of a document with contactless waves pulsing from the phone's top edge (where
/// the iPhone antenna is). Respects Reduce Motion.
struct VIDNFCTapAnimation: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private let navy = Color(
        red: VIDLayout.Fill.navy.red,
        green: VIDLayout.Fill.navy.green,
        blue: VIDLayout.Fill.navy.blue
    )

    var body: some View {
        ZStack {
            // Document lying flat (landscape), sitting lower.
            RoundedRectangle(cornerRadius: VIDLayout.Radius.doc)
                .fill(navy)
                .frame(width: VIDLayout.Size.nfcDocWidth, height: VIDLayout.Size.nfcDocHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: VIDLayout.Radius.chip)
                        .fill(tint)
                        .frame(width: VIDLayout.Size.nfcDocChipWidth, height: VIDLayout.Size.nfcDocChipHeight),
                    alignment: .center
                )
                .offset(y: VIDLayout.Size.nfcDocOffsetY)

            // Contactless waves pulsing up from the phone's top edge.
            ForEach(0 ..< 3) { i in
                VIDWaveArc()
                    .stroke(tint, style: StrokeStyle(lineWidth: VIDLayout.Stroke.wave, lineCap: .round))
                    .frame(width: VIDLayout.Size.nfcWaveWidth, height: VIDLayout.Size.nfcWaveHeight)
                    .scaleEffect(pulse ? VIDLayout.Scale.waveMax : VIDLayout.Scale.waveMin, anchor: .bottom)
                    .opacity(pulse ? .zero : VIDLayout.Opacity.waveVisible)
                    .offset(y: VIDLayout.Size.nfcWaveOffsetY)
                    .animation(
                        reduceMotion ? nil :
                            .easeOut(duration: VIDLayout.Duration.wavePulse).repeatForever(autoreverses: false)
                            .delay(Double(i) * VIDLayout.Duration.waveStagger),
                        value: pulse
                    )
            }

            // Phone resting on the top of the document.
            RoundedRectangle(cornerRadius: VIDLayout.Radius.phone)
                .fill(tint)
                .frame(width: VIDLayout.Size.nfcPhoneWidth, height: VIDLayout.Size.nfcPhoneHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: VIDLayout.Radius.phoneScreen)
                        .fill(Color.white.opacity(VIDLayout.Opacity.phoneScreen))
                        .frame(width: VIDLayout.Size.nfcScreenWidth, height: VIDLayout.Size.nfcScreenHeight)
                )
                .offset(y: VIDLayout.Size.nfcPhoneOffsetY)
        }
        .frame(width: VIDLayout.Size.nfcFrame, height: VIDLayout.Size.nfcFrame)
        .accessibilityHidden(true)
        .onAppear { pulse = true }
    }
}

/// An upward-bulging arc (a single contactless "wave").
struct VIDWaveArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(VIDLayout.Arc.start),
            endAngle: .degrees(VIDLayout.Arc.end),
            clockwise: false
        )
        return path
    }
}
