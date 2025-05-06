//
//  VIDTheme.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import SwiftUI

/// Semantic design tokens for every VerifID screen. Conform once, brand everything.
///
/// Customization ladder, shallow to deep:
/// 1. Conform to ``VIDTheme`` and apply with `.vidTheme(_:)` — colors, fonts, shape.
/// 2. Per-screen ViewBuilder overrides in `VerifIDUI`.
/// 3. Go fully headless — use `VerifIDNFC`/`VerifIDMRZ`/`VerifIDFace` directly
///    and build your own UI.
public protocol VIDTheme: Sendable {

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
    func font(_ role: VIDFontRole) -> Font
}

/// Semantic text roles used across VerifID screens.
public enum VIDFontRole: Sendable {
    case largeTitle, title, headline, body, caption, button
}

/// Neutral default theme. Adapts to light/dark mode and Dynamic Type.
public struct VIDDefaultTheme: VIDTheme {
    public init() {}

    public var background: Color { Color(uiColor: .systemBackground) }
    public var surface: Color { Color(uiColor: .secondarySystemBackground) }
    public var primary: Color { .blue }
    public var onPrimary: Color { .white }
    public var textPrimary: Color { Color(uiColor: .label) }
    public var textSecondary: Color { Color(uiColor: .secondaryLabel) }
    public var success: Color { .green }
    public var error: Color { .red }
    public var warning: Color { .orange }
    public var overlayScrim: Color { .black.opacity(0.55) }
    public var captureGuide: Color { .white }

    public var cornerRadius: CGFloat { 16 }
    public var buttonCornerRadius: CGFloat { 14 }
    public var screenPadding: CGFloat { 20 }

    public func font(_ role: VIDFontRole) -> Font {
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

// MARK: - Environment plumbing

private struct VIDThemeKey: EnvironmentKey {
    static let defaultValue: any VIDTheme = VIDDefaultTheme()
}

extension EnvironmentValues {
    /// The active VerifID theme. Read it in custom screen overrides.
    public var vidTheme: any VIDTheme {
        get { self[VIDThemeKey.self] }
        set { self[VIDThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies a custom brand theme to every VerifID screen in this hierarchy.
    ///
    /// ```swift
    /// VIDVerificationFlowView { result in ... }
    ///     .vidTheme(MyBrandTheme())
    /// ```
    public func vidTheme(_ theme: any VIDTheme) -> some View {
        environment(\.vidTheme, theme)
    }
}
