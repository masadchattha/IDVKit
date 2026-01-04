//
//  VIDFaceTutorialView.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 12/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import SwiftUI
import VerifIDCore

/// A short coaching screen shown before the live face check (gated by
/// ``VIDFaceConfiguration/showsTutorial``). It's a **swipeable pager** (no
/// auto-advance) whose pages are built from the **actual challenges that were
/// picked for this session** plus the mode — so the user only ever previews the
/// exact prompts they'll be asked. Each page animates a native line-drawn face.
struct VIDFaceTutorialView: View {
    let mode: VIDLivenessMode
    /// The challenges chosen for this session (drives which pages appear).
    let challenges: [VIDLivenessChallenge]
    let onStart: () -> Void
    let onCancel: () -> Void

    @Environment(\.vidTheme) private var theme
    @State private var page = 0

    var body: some View {
        let pages = Self.pages(mode: mode, challenges: challenges)
        VStack(spacing: theme.screenPadding) {
            Spacer()

            Text(VIDStrings.Tutorial.title, bundle: .module)
                .font(theme.font(.largeTitle))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: VIDLayout.Spacing.large) {
                        VIDTutorialFace(action: pages[index].action, tint: theme.primary, idle: theme.textSecondary)
                        Text(pages[index].caption, bundle: .module)
                            .font(theme.font(.body))
                            .foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, theme.screenPadding)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: VIDLayout.Size.tutorialPagerHeight)

            // Custom dots — the system ones are invisible in light mode. Theme-aware
            // and only shown when there's more than one page.
            if pages.count > 1 {
                HStack(spacing: VIDLayout.Spacing.small) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle()
                            .fill(index == page ? theme.primary : theme.textSecondary.opacity(VIDLayout.Opacity.subtle))
                            .frame(width: VIDLayout.Size.pagerDot, height: VIDLayout.Size.pagerDot)
                    }
                }
                .animation(.easeInOut, value: page)
            }

            Spacer()

            primaryButton(VIDStrings.Button.start, action: onStart)
            secondaryButton(VIDStrings.Button.cancel, action: onCancel)
        }
        .padding(theme.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }

    /// The pages to show: one per actual challenge (when the mode uses them), then
    /// the head-rotation page (when the mode uses it). Passive shows a hold page.
    static func pages(mode: VIDLivenessMode, challenges: [VIDLivenessChallenge]) -> [(action: VIDFaceAction, caption: LocalizedStringKey)] {
        if mode == .passive {
            return [(.hold, VIDStrings.Tutorial.pageHold)]
        }
        var pages: [(VIDFaceAction, LocalizedStringKey)] = []
        if mode.usesActiveChallenges {
            for challenge in challenges {
                pages.append(page(for: challenge))
            }
        }
        if mode.usesHeadRotation {
            pages.append((.rotate, VIDStrings.Tutorial.pageRotate))
        }
        // Fallback so there's always at least one page.
        return pages.isEmpty ? [(.rotate, VIDStrings.Tutorial.pageRotate)] : pages
    }

    private static func page(for challenge: VIDLivenessChallenge) -> (VIDFaceAction, LocalizedStringKey) {
        switch challenge {
        case .blinkLeft: (.blink, VIDStrings.Tutorial.pageBlinkLeft)
        case .blinkRight: (.blink, VIDStrings.Tutorial.pageBlinkRight)
        case .smile: (.smile, VIDStrings.Tutorial.pageSmile)
        case .openMouth: (.openMouth, VIDStrings.Tutorial.pageOpenMouth)
        case .turnLeft: (.turnLeft, VIDStrings.Tutorial.pageTurnLeft)
        case .turnRight: (.turnRight, VIDStrings.Tutorial.pageTurnRight)
        }
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title, bundle: .module)
                .font(theme.font(.button))
                .foregroundStyle(theme.onPrimary)
                .frame(maxWidth: .infinity, minHeight: VIDLayout.Size.buttonHeight)
                .background(theme.primary, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
        }
    }

    private func secondaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title, bundle: .module)
                .font(theme.font(.button))
                .foregroundStyle(theme.textSecondary)
        }
    }
}

/// The action a tutorial page demonstrates.
enum VIDFaceAction {
    case position, rotate, blink, smile, openMouth, turnLeft, turnRight, hold
}

/// A native line-drawn face that animates the given ``VIDFaceAction``. Freezes to a
/// calm resting state under Reduce Motion.
struct VIDTutorialFace: View {
    let action: VIDFaceAction
    let tint: Color
    let idle: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let segmentCount = 44
    private let cycle = 2.0
    private static let turnDegrees = 26.0

    var body: some View {
        let idleTick = idle.opacity(VIDLayout.Opacity.ringInactive)
        let circle = CGSize(width: VIDLayout.Size.tutorialCircle, height: VIDLayout.Size.tutorialCircle)
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = reduceMotion ? 1 : Self.phase(at: context.date, cycle: cycle)
            let state = state(phase: phase)
            ZStack {
                VIDHeadRotationRing(
                    filled: ringFilled(state.ringFill),
                    ovalSize: circle, activeColor: tint, idleColor: idleTick
                )
                VIDSmileyFace(
                    tint: idle, diameter: VIDLayout.Size.tutorialCircle,
                    eyeOpen: state.eyeOpen, smileDepth: state.smileDepth, mouthOpen: state.mouthOpen
                )
                .rotation3DEffect(.degrees(state.turn), axis: (x: 0, y: 1, z: 0))
            }
            .frame(width: VIDLayout.Size.tutorialDemo, height: VIDLayout.Size.tutorialDemo)
        }
        .accessibilityHidden(true)
    }

    private func ringFilled(_ fill: Double) -> [Bool] {
        (0 ..< segmentCount).map { Double($0) / Double(segmentCount) <= fill }
    }

    private struct FaceState {
        var eyeOpen: CGFloat = 1
        var smileDepth: CGFloat = 0.85
        var mouthOpen: CGFloat = 0
        var ringFill: Double = 0
        var turn: Double = 0
    }

    /// Resolves the animated face parameters for the current phase and action.
    private func state(phase: Double) -> FaceState {
        switch action {
        case .position, .hold:
            return FaceState()
        case .rotate:
            return FaceState(ringFill: reduceMotion ? 1 : phase)
        case .blink:
            let closeness = abs(phase - 0.5)
            let eyeOpen = reduceMotion ? 1 : CGFloat(min(1, closeness / 0.06))
            return FaceState(eyeOpen: eyeOpen)
        case .smile:
            let depth = reduceMotion ? 1 : CGFloat((1 - cos(phase * 2 * .pi)) / 2)
            return FaceState(smileDepth: depth)
        case .openMouth:
            let open = reduceMotion ? 1 : CGFloat((1 - cos(phase * 2 * .pi)) / 2)
            return FaceState(smileDepth: 0.4, mouthOpen: open)
        case .turnLeft:
            let turn = reduceMotion ? -Self.turnDegrees : -Self.turnDegrees * (1 - cos(phase * 2 * .pi)) / 2
            return FaceState(turn: turn)
        case .turnRight:
            let turn = reduceMotion ? Self.turnDegrees : Self.turnDegrees * (1 - cos(phase * 2 * .pi)) / 2
            return FaceState(turn: turn)
        }
    }

    static func phase(at date: Date, cycle: Double) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
    }
}

/// A simple line-drawn face (circle, two dot eyes, a mouth) matching the one Apple
/// shows during Face ID enrollment. `eyeOpen` (0…1) blinks, `smileDepth` (0…1)
/// curves the mouth, and `mouthOpen` (0…1) opens it into an oval.
struct VIDSmileyFace: View {
    let tint: Color
    let diameter: CGFloat
    var eyeOpen: CGFloat = 1
    var smileDepth: CGFloat = 0.85
    var mouthOpen: CGFloat = 0

    // Proportions of the face diameter.
    private static let eyeSize = 0.085
    private static let eyeSpacing = 0.28
    private static let eyeOffsetY = 0.11
    private static let eyeMinOpen = 0.12
    private static let smileWidth = 0.46
    private static let smileHeight = 0.19
    private static let smileOffsetY = 0.15
    private static let openMouthShow = 0.05

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint, lineWidth: VIDLayout.Stroke.regular)
                .frame(width: diameter, height: diameter)
            HStack(spacing: diameter * Self.eyeSpacing) {
                eye
                eye
            }
            .offset(y: -diameter * Self.eyeOffsetY)
            mouth
                .offset(y: diameter * Self.smileOffsetY)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mouth: some View {
        if mouthOpen > Self.openMouthShow {
            Ellipse()
                .stroke(tint, lineWidth: VIDLayout.Stroke.regular)
                .frame(width: diameter * Self.smileWidth * 0.7,
                       height: diameter * Self.smileHeight * (0.6 + mouthOpen))
        } else {
            VIDSmileArc(depth: smileDepth)
                .stroke(tint, style: StrokeStyle(lineWidth: VIDLayout.Stroke.regular, lineCap: .round))
                .frame(width: diameter * Self.smileWidth, height: diameter * Self.smileHeight)
        }
    }

    private var eye: some View {
        Circle()
            .fill(tint)
            .frame(width: diameter * Self.eyeSize, height: diameter * Self.eyeSize)
            .scaleEffect(y: max(Self.eyeMinOpen, eyeOpen))
    }
}

/// An upturned-mouth arc for ``VIDSmileyFace``. `depth` 0 is a flat line, 1 a full
/// smile; it's animatable so a page can ease the mouth open.
struct VIDSmileArc: Shape {
    var depth: CGFloat = 0.85

    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + (rect.maxY - rect.minY) * 2 * depth)
        )
        return path
    }
}
