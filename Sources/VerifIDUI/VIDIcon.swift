//
//  VIDIcon.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 19/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation

/// SF Symbol names used across the drop-in UI. Keeping them here means no raw
/// symbol strings live in view bodies (a single place to audit/rename icons).
enum VIDIcon {
    // Hero symbols (fallbacks when no illustration is supplied)
    static let intro = "person.text.rectangle"
    static let documentScan = "doc.viewfinder"
    static let faceIntro = "person.crop.square"
    static let chipGuidance = "wave.3.right"

    // Guidance rows
    static let restPhone = "rectangle.portrait.and.arrow.forward"
    static let holdStill = "hand.raised.fill"
    static let phoneCase = "iphone.gen3"

    // Components
    static let chevron = "chevron.right"
    static let warning = "exclamationmark.triangle.fill"
    static let securedBadge = "lock.shield.fill"
    static let faceMatch = "equal.circle.fill"
    static let faceMismatch = "xmark.circle.fill"
    static let debugPhoto = "photo.on.rectangle"
    static let close = "xmark.circle.fill"
    static let multipleFaces = "person.2.slash.fill"
    static let lowLight = "lightbulb.slash.fill"

    // Result badges
    static let mrzMatchesChip = "checkmark.circle.fill"
    static let chipVerified = "checkmark.seal.fill"
    static let chipDataIntact = "checkmark.shield.fill"
    static let chipUnverifiable = "exclamationmark.shield.fill"
    static let genuineChip = "cpu.fill"
    static let chipAuthFailed = "cpu"
    static let faceMatchBadge = "person.crop.circle.badge.checkmark"
    static let faceMismatchBadge = "person.crop.circle.badge.xmark"

    /// Document-kind icons shown on the document-selection card.
    enum Document {
        static let passport = "book.pages"
        static let idCard = "person.text.rectangle"
        static let residencePermit = "creditcard"
        static let any = "doc.text.image"
    }

    /// Liveness challenge glyphs shown above the instruction text.
    enum Challenge {
        static let blink = "eye"
        static let smile = "face.smiling"
        static let openMouth = "mouth"
        static let turnLeft = "arrow.left"
        static let turnRight = "arrow.right"
    }
}
