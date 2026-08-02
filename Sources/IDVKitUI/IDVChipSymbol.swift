//
//  IDVChipSymbol.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import SwiftUI

/// An original glyph evoking the "chip inside" mark printed on eMRTD documents (a
/// document outline enclosing a chip circle and antenna bar). Drawn from scratch
/// rather than shipping the ICAO/EMVCo artwork, which is trademark-controlled.
struct IDVChipSymbol: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: IDVLayout.Radius.glyph)
            .stroke(tint, lineWidth: IDVLayout.Stroke.regular)
            .frame(width: IDVLayout.Size.chipGlyphWidth, height: IDVLayout.Size.chipGlyphHeight)
            .overlay {
                VStack(spacing: IDVLayout.Spacing.tiny) {
                    Circle()
                        .stroke(tint, lineWidth: IDVLayout.Stroke.regular)
                        .frame(width: IDVLayout.Size.chipGlyphCircle, height: IDVLayout.Size.chipGlyphCircle)
                    Capsule()
                        .fill(tint)
                        .frame(width: IDVLayout.Size.chipGlyphBarWidth, height: IDVLayout.Size.chipGlyphBarHeight)
                }
            }
            .accessibilityHidden(true)
    }
}
