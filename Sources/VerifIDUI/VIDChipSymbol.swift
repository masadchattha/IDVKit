//
//  VIDChipSymbol.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import SwiftUI

/// An original glyph evoking the "chip inside" mark printed on eMRTD documents (a
/// document outline enclosing a chip circle and antenna bar). Drawn from scratch
/// rather than shipping the ICAO/EMVCo artwork, which is trademark-controlled.
struct VIDChipSymbol: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: VIDLayout.Radius.glyph)
            .stroke(tint, lineWidth: VIDLayout.Stroke.regular)
            .frame(width: VIDLayout.Size.chipGlyphWidth, height: VIDLayout.Size.chipGlyphHeight)
            .overlay {
                VStack(spacing: VIDLayout.Spacing.tiny) {
                    Circle()
                        .stroke(tint, lineWidth: VIDLayout.Stroke.regular)
                        .frame(width: VIDLayout.Size.chipGlyphCircle, height: VIDLayout.Size.chipGlyphCircle)
                    Capsule()
                        .fill(tint)
                        .frame(width: VIDLayout.Size.chipGlyphBarWidth, height: VIDLayout.Size.chipGlyphBarHeight)
                }
            }
            .accessibilityHidden(true)
    }
}
