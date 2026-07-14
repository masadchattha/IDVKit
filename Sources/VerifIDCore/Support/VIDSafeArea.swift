//
//  VIDSafeArea.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

#if canImport(UIKit)
import SwiftUI
import UIKit

package extension EdgeInsets {
    /// The key window's real safe-area insets.
    ///
    /// Full-bleed camera screens apply `.ignoresSafeArea()` to their
    /// `GeometryReader` so the preview and overlays fill the display — but that
    /// zeroes the proxy's `safeAreaInsets`, so the on-screen chrome (close button,
    /// bottom prompts) can't use it to clear the notch / Dynamic Island / home
    /// indicator. This reads the true insets from the key window instead.
    @MainActor
    static var vidKeyWindowSafeArea: EdgeInsets {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        let insets = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }
}
#endif
