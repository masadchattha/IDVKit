//
//  VIDHelpAlert.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import SwiftUI

extension View {
    /// A simple "tips" help alert — a title, a bulleted message, and a dismiss
    /// button — shown from the top-bar Help button on the scan/face screens.
    func vidHelpAlert(isPresented: Binding<Bool>, title: LocalizedStringKey, tips: LocalizedStringKey) -> some View {
        alert(title, isPresented: isPresented) {
            Button(role: .cancel) {} label: { Text(VIDStrings.Help.ok, bundle: .module) }
        } message: {
            Text(tips, bundle: .module)
        }
    }

    /// Tips for reading the passport/ID chip over NFC.
    func vidNFCHelpAlert(isPresented: Binding<Bool>) -> some View {
        vidHelpAlert(isPresented: isPresented, title: VIDStrings.Help.nfcTitle, tips: VIDStrings.Help.nfcTips)
    }

    /// Tips for the face check.
    func vidFaceHelpAlert(isPresented: Binding<Bool>) -> some View {
        vidHelpAlert(isPresented: isPresented, title: VIDStrings.Help.faceTitle, tips: VIDStrings.Help.faceTips)
    }
}
