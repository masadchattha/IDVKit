//
//  IDVNFCTapAnimation.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import SwiftUI

/// A dependency-free animated coach for the NFC step: a phone resting on the top
/// of a document with contactless waves pulsing from the phone's top edge (where
/// the iPhone antenna is). Respects Reduce Motion.
struct IDVNFCTapAnimation: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private let navy = Color(
        red: IDVLayout.Fill.navy.red,
        green: IDVLayout.Fill.navy.green,
        blue: IDVLayout.Fill.navy.blue
    )

    var body: some View {
        ZStack {
            // Document lying flat (landscape), sitting lower.
            RoundedRectangle(cornerRadius: IDVLayout.Radius.doc)
                .fill(navy)
                .frame(width: IDVLayout.Size.nfcDocWidth, height: IDVLayout.Size.nfcDocHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: IDVLayout.Radius.chip)
                        .fill(tint)
                        .frame(width: IDVLayout.Size.nfcDocChipWidth, height: IDVLayout.Size.nfcDocChipHeight),
                    alignment: .center
                )
                .offset(y: IDVLayout.Size.nfcDocOffsetY)

            // Contactless waves pulsing up from the phone's top edge.
            ForEach(0 ..< 3) { i in
                IDVWaveArc()
                    .stroke(tint, style: StrokeStyle(lineWidth: IDVLayout.Stroke.wave, lineCap: .round))
                    .frame(width: IDVLayout.Size.nfcWaveWidth, height: IDVLayout.Size.nfcWaveHeight)
                    .scaleEffect(pulse ? IDVLayout.Scale.waveMax : IDVLayout.Scale.waveMin, anchor: .bottom)
                    .opacity(pulse ? .zero : IDVLayout.Opacity.waveVisible)
                    .offset(y: IDVLayout.Size.nfcWaveOffsetY)
                    .animation(
                        reduceMotion ? nil :
                            .easeOut(duration: IDVLayout.Duration.wavePulse).repeatForever(autoreverses: false)
                            .delay(Double(i) * IDVLayout.Duration.waveStagger),
                        value: pulse
                    )
            }

            // Phone resting on the top of the document.
            RoundedRectangle(cornerRadius: IDVLayout.Radius.phone)
                .fill(tint)
                .frame(width: IDVLayout.Size.nfcPhoneWidth, height: IDVLayout.Size.nfcPhoneHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: IDVLayout.Radius.phoneScreen)
                        .fill(Color.white.opacity(IDVLayout.Opacity.phoneScreen))
                        .frame(width: IDVLayout.Size.nfcScreenWidth, height: IDVLayout.Size.nfcScreenHeight)
                )
                .offset(y: IDVLayout.Size.nfcPhoneOffsetY)
        }
        .frame(width: IDVLayout.Size.nfcFrame, height: IDVLayout.Size.nfcFrame)
        .accessibilityHidden(true)
        .onAppear { pulse = true }
    }
}

/// An upward-bulging arc (a single contactless "wave").
struct IDVWaveArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(IDVLayout.Arc.start),
            endAngle: .degrees(IDVLayout.Arc.end),
            clockwise: false
        )
        return path
    }
}
