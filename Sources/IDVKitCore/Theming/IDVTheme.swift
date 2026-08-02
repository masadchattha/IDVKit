//
//  IDVTheme.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import SwiftUI

/// Semantic design tokens for every IDVKit screen. Conform once, brand everything.
///
/// Customization ladder, shallow to deep:
/// 1. Conform to ``IDVTheme`` and apply with `.idvTheme(_:)` — colors, fonts, shape.
/// 2. Per-screen ViewBuilder overrides in `IDVKitUI`.
/// 3. Go fully headless — use `IDVKitNFC`/`IDVKitMRZ`/`IDVKitFace` directly
///    and build your own UI.
public protocol IDVTheme: Sendable {
    // MARK: Colors

    var background: Color { get }
    var surface: Color { get }
    /// Brand/action color — buttons, progress, active states.
    var primary: Color { get }
    /// Content drawn on top of ``primary``.
    var onPrimary: Color { get }
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var success: Color { get }
    var error: Color { get }
    var warning: Color { get }
    /// Dimming layer behind camera cutouts and sheets.
    var overlayScrim: Color { get }
    /// Stroke color of capture guides (MRZ frame, face oval, scan line).
    var captureGuide: Color { get }

    // MARK: Shape & spacing

    var cornerRadius: CGFloat { get }
    var buttonCornerRadius: CGFloat { get }
    var screenPadding: CGFloat { get }

    // MARK: Typography

    /// Font for a semantic text role. Return your brand font here.
    func font(_ role: IDVFontRole) -> Font
}

/// Semantic text roles used across IDVKit screens.
public enum IDVFontRole: Sendable {
    case largeTitle, title, headline, body, caption, button
}

/// Neutral default theme. Adapts to light/dark mode and Dynamic Type.
public struct IDVDefaultTheme: IDVTheme {
    /// The primary/accent color for buttons, icons, and highlights.
    public var accent: Color

    /// A calm cornflower/indigo — the trust-forward tone identity flows converge on.
    public static let defaultAccent = Color(
        red: 0x6C / 255, green: 0x63 / 255, blue: 0xFF / 255
    )

    /// Creates the default theme, optionally overriding just the accent color —
    /// the simplest way to brand the flow without writing a full ``IDVTheme``:
    ///
    /// ```swift
    /// IDVVerificationFlowView { /* … */ }
    ///     .idvTheme(IDVDefaultTheme(accent: .indigo))
    /// ```
    public init(accent: Color = IDVDefaultTheme.defaultAccent) {
        self.accent = accent
    }

    public var background: Color {
        Color(uiColor: .systemBackground)
    }

    public var surface: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    public var primary: Color {
        accent
    }

    public var onPrimary: Color {
        .white
    }

    public var textPrimary: Color {
        Color(uiColor: .label)
    }

    public var textSecondary: Color {
        Color(uiColor: .secondaryLabel)
    }

    public var success: Color {
        .green
    }

    public var error: Color {
        .red
    }

    public var warning: Color {
        .orange
    }

    public var overlayScrim: Color {
        .black.opacity(0.55)
    }

    public var captureGuide: Color {
        .white
    }

    public var cornerRadius: CGFloat {
        16
    }

    public var buttonCornerRadius: CGFloat {
        14
    }

    public var screenPadding: CGFloat {
        20
    }

    public func font(_ role: IDVFontRole) -> Font {
        switch role {
        case .largeTitle: .largeTitle.bold()
        case .title: .title2.bold()
        case .headline: .headline
        case .body: .body
        case .caption: .caption
        case .button: .headline
        }
    }
}

extension EnvironmentValues {
    /// The active IDVKit theme. Read it in custom screen overrides.
    @Entry public var idvTheme: any IDVTheme = IDVDefaultTheme()
}

extension View {
    /// Applies a custom brand theme to every IDVKit screen in this hierarchy.
    ///
    /// ```swift
    /// IDVVerificationFlowView { result in ... }
    ///     .idvTheme(MyBrandTheme())
    /// ```
    public func idvTheme(_ theme: any IDVTheme) -> some View {
        environment(\.idvTheme, theme)
    }
}
