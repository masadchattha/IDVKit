//
//  IDVHelpAlert.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import SwiftUI

extension View {
    /// A simple "tips" help alert — a title, a bulleted message, and a dismiss
    /// button — shown from the top-bar Help button on the scan/face screens.
    func idvHelpAlert(isPresented: Binding<Bool>, title: LocalizedStringKey, tips: LocalizedStringKey) -> some View {
        alert(title, isPresented: isPresented) {
            Button(role: .cancel) {} label: { Text(IDVStrings.Help.ok, bundle: .module) }
        } message: {
            Text(tips, bundle: .module)
        }
    }

    /// Tips for reading the passport/ID chip over NFC.
    func idvNFCHelpAlert(isPresented: Binding<Bool>) -> some View {
        idvHelpAlert(isPresented: isPresented, title: IDVStrings.Help.nfcTitle, tips: IDVStrings.Help.nfcTips)
    }

    /// Tips for the face check.
    func idvFaceHelpAlert(isPresented: Binding<Bool>) -> some View {
        idvHelpAlert(isPresented: isPresented, title: IDVStrings.Help.faceTitle, tips: IDVStrings.Help.faceTips)
    }
}
