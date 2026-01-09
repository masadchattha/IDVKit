//
//  VIDColor.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import SwiftUI

/// Fixed, non-themeable colours for the face capture. These are deliberately the
/// system green/gray values rather than theme tokens, so the ring reads exactly
/// like the Face-ID reference. They are chosen to hold contrast on **both** the
/// light and dark capture backgrounds (the capture follows the system appearance),
/// which is why the unlit tick is full-strength system gray rather than a faded one.
enum VIDColor {
    /// A lit head-rotation tick — Apple dark-mode systemGreen (#30D158).
    static let tickLit = Color(red: 48.0 / 255, green: 209.0 / 255, blue: 88.0 / 255)
    /// An unlit tick — systemGray (#8E8E93). A true mid-gray, so it stays legible
    /// against white in light appearance and against black in dark appearance.
    static let tickIdle = Color(red: 142.0 / 255, green: 142.0 / 255, blue: 147.0 / 255)
    /// The dark placeholder shown in the capture circle during the Simulator
    /// design-preview (stands in for the live camera).
    static let cameraPlaceholder = Color(white: 0.14)
    /// The face glyph on the design-preview placeholder.
    static let cameraPlaceholderGlyph = Color(white: 0.4)

    /// The rotating halo palette for ``VIDSiriGlow`` — decorative and fixed, so it
    /// lives here with the other non-themeable capture colours.
    static let glowPalette: [Color] = [.purple, .blue, .cyan, Color(red: 0.42, green: 0.39, blue: 1.0), .purple]
}
