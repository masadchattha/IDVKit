//
//  IDVFaceCaptureView.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 12/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Combine
import CoreGraphics
import IDVKitCore
import IDVKitFace
import OSLog
import SwiftUI
import UIKit

/// Full-screen active-liveness capture: the user completes a couple of randomised
/// challenges (with brief grace-period pauses so each instruction is readable),
/// a neutral still is captured, and it's matched against the document portrait.
/// Clean, themed UI over ``IDVLivenessARView``.
public struct IDVFaceCaptureView: View {
    let reference: CGImage
    let configuration: IDVFaceConfiguration
    let onComplete: (IDVLivenessOutcome, IDVFaceMatchResult) -> Void
    let onCancel: () -> Void
    /// DEBUG design-review only: renders the capture UI with a placeholder instead
    /// of the live camera and auto-drives the ring, so the design can be seen in
    /// the Simulator (which has no camera). Always `false` in shipping builds.
    private let debugDesignPreview: Bool

    @Environment(\.idvTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: Model
    @State private var showFaceHelp = false

    public init(
        reference: CGImage,
        configuration: IDVFaceConfiguration = .init(),
        onComplete: @escaping (IDVLivenessOutcome, IDVFaceMatchResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.reference = reference
        self.configuration = configuration
        self.onComplete = onComplete
        self.onCancel = onCancel
        debugDesignPreview = false
        _model = StateObject(wrappedValue: Model(reference: reference, configuration: configuration,
                                                 onComplete: onComplete, onCancel: onCancel))
    }

    #if DEBUG
        /// DEBUG-only: renders the capture design in the Simulator with a
        /// placeholder camera and an auto-filling ring. Not shipping API.
        public init(designPreview reference: CGImage, configuration: IDVFaceConfiguration = .init(),
                    onCancel: @escaping () -> Void = {}) {
            self.reference = reference
            self.configuration = configuration
            onComplete = { _, _ in }
            self.onCancel = onCancel
            debugDesignPreview = true
            _model = StateObject(wrappedValue: Model(reference: reference, configuration: configuration,
                                                     onComplete: { _, _ in }, onCancel: onCancel, debugDesignPreview: true))
        }
    #endif

    public var body: some View {
        GeometryReader { geo in
            let oval = ovalRect(in: geo.size)
            ZStack {
                // Tutorial and live capture are mutually exclusive full screens, so
                // one cleanly replaces the other — the camera/oval never bleeds
                // through a cross-fade, and the front camera isn't started until the
                // user leaves the tutorial.
                if model.step == .tutorial {
                    IDVFaceTutorialView(mode: configuration.livenessMode, challenges: model.challenges,
                                        onStart: model.beginLiveness, onCancel: model.cancel)
                } else {
                    // Apple Face-ID layout: pure-black screen with the camera shown
                    // ONLY inside the circle (never full-screen), a soft Siri-style
                    // glow, then the tick ring around it.
                    cameraCircle(oval)

                    if model.showsGlow {
                        IDVSiriGlow(diameter: oval.width + IDVLayout.Glow.inset)
                            .position(x: oval.midX, y: oval.midY)
                    }

                    Circle()
                        .stroke(ovalColor, style: .init(lineWidth: IDVLayout.Stroke.hairline, lineCap: .round))
                        .frame(width: oval.width, height: oval.height)
                        .position(x: oval.midX, y: oval.midY)
                        .scaleEffect(model.showPulse ? IDVLayout.Scale.ovalPulse : 1.0)
                        .animation(.easeOut(duration: IDVLayout.Duration.ovalPulse), value: model.showPulse)
                        .animation(.easeInOut(duration: IDVLayout.Duration.ovalStateChange), value: model.ovalState)

                    // Uniform tick ring for the head-rotation phase; it stays visible
                    // (fully filled) through the neutral-pose capture.
                    if model.showsRing {
                        IDVHeadRotationRing(
                            filled: model.ringFilled,
                            ovalSize: CGSize(width: oval.width, height: oval.height),
                            activeColor: IDVColor.tickLit,
                            idleColor: IDVColor.tickIdle
                        )
                        .position(x: oval.midX, y: oval.midY)
                    }

                    chrome(oval: oval, safeArea: realSafeAreaInsets)

                    if model.step == .processing {
                        processingOverlay
                    }
                    if model.step == .success {
                        successOverlay
                    }
                    if case let .failed(message) = model.step {
                        failureOverlay(message)
                    }
                }
            }
        }
        .ignoresSafeArea()
        // Follows the system theme: white in light, black in dark.
        .background(theme.background)
        .idvFaceHelpAlert(isPresented: $showFaceHelp)
        .onAppear {
            model.prefersReducedMotion = reduceMotion
            model.start()
        }
        .onDisappear(perform: model.stop)
    }

    /// The live camera (or a placeholder in the Simulator design-preview) shown
    /// ONLY inside the circle, on the black background — Apple's framing.
    private func cameraCircle(_ oval: CGRect) -> some View {
        Group {
            #if DEBUG
                if debugDesignPreview {
                    ZStack {
                        IDVColor.cameraPlaceholder
                        Image(systemName: IDVIcon.faceIntro)
                            .font(.system(size: oval.width * IDVLayout.Scale.placeholderGlyph))
                            .foregroundStyle(IDVColor.cameraPlaceholderGlyph)
                    }
                } else {
                    liveCamera
                }
            #else
                liveCamera
            #endif
        }
        .frame(width: oval.width, height: oval.height)
        .clipShape(Circle())
        .position(x: oval.midX, y: oval.midY)
    }

    private var liveCamera: some View {
        IDVLivenessARView(
            onFrame: model.handleFrame,
            onFaceLost: model.handleFaceLost,
            onCapture: model.handleCapture,
            onLightEstimate: model.handleLight,
            onFaceCount: model.handleFaceCount,
            onUnsupported: model.handleUnsupported,
            captureRequested: $model.captureRequested,
            sessionPaused: $model.sessionPaused
        )
    }

    // MARK: Layout

    /// The window's true safe-area insets (the `GeometryReader` ignores the safe
    /// area so the camera and overlays fill the screen, which zeroes its proxy).
    private var realSafeAreaInsets: EdgeInsets {
        .idvKeyWindowSafeArea
    }

    /// The face guide is a **circle** (Apple Face-ID style): a square rect rendered
    /// with `Ellipse`, so the camera mask, the guide stroke, and the tick ring are
    /// all circular and concentric.
    private func ovalRect(in size: CGSize) -> CGRect {
        let diameter = min(size.width * IDVLayout.Size.captureCircleFactor, IDVLayout.Size.ovalMaxWidth)
        return CGRect(
            x: (size.width - diameter) / 2,
            y: size.height * IDVLayout.Size.ovalVerticalPositionFactor - diameter / 2,
            width: diameter, height: diameter
        )
    }

    private var ovalColor: Color {
        // Theme-aware, deliberately faint — the ring/glow lead, not a heavy edge.
        switch model.ovalState {
        case .idle: theme.textSecondary.opacity(IDVLayout.Opacity.ovalIdle)
        case .adjusting: theme.warning
        case .active: theme.textSecondary.opacity(IDVLayout.Opacity.subtle)
        case .success: theme.success
        case .error: theme.error
        }
    }

    // MARK: Chrome

    private func chrome(oval: CGRect, safeArea: EdgeInsets) -> some View {
        VStack(spacing: .zero) {
            HStack {
                Button(action: model.cancel) {
                    Text(IDVStrings.Button.cancel, bundle: .module)
                        .font(theme.font(.button))
                        .foregroundStyle(theme.textPrimary)
                }
                Spacer()
                Button { showFaceHelp = true } label: {
                    Label(IDVStrings.Help.button, systemImage: IDVIcon.help)
                        .font(theme.font(.button))
                        .foregroundStyle(theme.primary)
                }
            }
            .padding(.horizontal, theme.screenPadding)
            .padding(.top, max(safeArea.top, IDVLayout.Spacing.medium))

            // One banner at a time; a second face is the more urgent warning.
            Group {
                if model.multipleFaces {
                    warningBanner(IDVStrings.FaceCapture.multipleFacesWarning, systemImage: IDVIcon.multipleFaces)
                } else if model.isLowLight {
                    lowLightBanner
                }
            }
            .padding(.top, IDVLayout.Spacing.medium)
            .animation(.easeInOut(duration: IDVLayout.Duration.bannerToggle), value: model.multipleFaces)
            .animation(.easeInOut(duration: IDVLayout.Duration.bannerToggle), value: model.isLowLight)

            Spacer()

            // Bottom HUD — hidden while a processing/failure overlay is shown so
            // stale prompts (e.g. "Hold still…") never bleed through.
            if model.showsHUD {
                VStack(spacing: IDVLayout.Spacing.large) {
                    if model.showsChallengeDots {
                        challengeProgress
                    }

                    // Fixed-height icon slot so the text below never jumps when the
                    // icon appears/disappears between a challenge and the neutral pose.
                    ZStack {
                        if let icon = model.challengeIcon {
                            Image(systemName: icon)
                                .font(.system(size: IDVLayout.IconSize.challenge, weight: .semibold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                                .id(icon)
                        }
                    }
                    .frame(height: IDVLayout.Size.challengeIconSlotHeight)
                    .animation(
                        .spring(response: IDVLayout.Spring.challengeIconResponse, dampingFraction: IDVLayout.Spring.challengeIconDamping),
                        value: model.challengeIcon
                    )

                    Text(model.instruction)
                        .font(theme.font(.title))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, theme.screenPadding)
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: model.instruction)

                    // Accessibility escape hatch during the head-rotation phase —
                    // mirrors Face ID's "Accessibility Options": skip the rotation
                    // and capture from a steady frontal hold instead.
                    if model.step == .headRotation {
                        Button(action: model.skipHeadRotation) {
                            Text(IDVStrings.FaceCapture.accessibilityOptions, bundle: .module)
                                .font(theme.font(.button))
                                .foregroundStyle(theme.primary)
                        }
                    }
                }
                .padding(.bottom, max(safeArea.bottom, IDVLayout.Spacing.large) + IDVLayout.Spacing.hudBottomExtra)
                .transition(.opacity)
            }
        }
    }

    /// "Step N of M" progress for the challenge sequence, shown above the prompt.
    private var challengeProgress: some View {
        HStack(spacing: IDVLayout.Spacing.small) {
            ForEach(model.challenges.indices, id: \.self) { index in
                Capsule()
                    .fill(index < model.completedCount ? theme.success : Color.white.opacity(IDVLayout.Opacity.subtle))
                    .frame(
                        width: index < model.completedCount
                            ? IDVLayout.Size.challengeCapsuleActiveWidth
                            : IDVLayout.Size.challengeCapsuleInactiveWidth,
                        height: IDVLayout.Size.challengeCapsuleHeight
                    )
                    .animation(.easeInOut, value: model.completedCount)
            }
        }
    }

    private var lowLightBanner: some View {
        Label {
            Text(IDVStrings.FaceCapture.lowLightWarning, bundle: .module)
        } icon: {
            Image(systemName: IDVIcon.lowLight)
        }
        .font(theme.font(.caption))
        .foregroundStyle(.white)
        .padding(.horizontal, IDVLayout.Spacing.row).padding(.vertical, IDVLayout.Spacing.small)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// A prominent, filled warning pill (e.g. a second face in view).
    private func warningBanner(_ textKey: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(textKey, bundle: .module)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(theme.font(.body))
        .foregroundStyle(.white)
        .padding(.horizontal, IDVLayout.Spacing.large).padding(.vertical, IDVLayout.Spacing.title)
        .background(theme.warning, in: Capsule())
        .shadow(color: .black.opacity(IDVLayout.Opacity.bannerShadow), radius: IDVLayout.Shadow.bannerRadius, y: IDVLayout.Shadow.bannerY)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(IDVLayout.Opacity.processingScrim).ignoresSafeArea()
            VStack(spacing: IDVLayout.Spacing.large) {
                ProgressView().controlSize(.large).tint(.white)
                Text(IDVStrings.FaceCapture.verifying, bundle: .module)
                    .font(theme.font(.headline)).foregroundStyle(.white)
            }
        }
    }

    /// A brief green checkmark held before the flow advances (the success signal
    /// lands on the element the user is already looking at — the oval turned
    /// green — then this confirms it).
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(IDVLayout.Opacity.successScrim).ignoresSafeArea()
            ZStack {
                Circle()
                    .fill(theme.success)
                    .frame(width: IDVLayout.Size.successBadge, height: IDVLayout.Size.successBadge)
                Image(systemName: IDVIcon.success)
                    .font(.system(size: IDVLayout.IconSize.success, weight: .bold))
                    .foregroundStyle(theme.onPrimary)
            }
            .transition(.scale.combined(with: .opacity))
            Text(IDVStrings.FaceCapture.allSet, bundle: .module)
                .font(theme.font(.title))
                .foregroundStyle(.white)
                .offset(y: IDVLayout.Size.successBadge)
        }
        .accessibilityElement()
        .accessibilityLabel(IDVStrings.FaceCapture.allSet)
    }

    /// A clean, full-screen themed failure screen (not cramped over the camera):
    /// a soft error badge, a friendly title, the specific reason, then the actions.
    private func failureOverlay(_ message: String) -> some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            ZStack {
                Circle()
                    .fill(theme.error.opacity(IDVLayout.Opacity.tint))
                    .frame(width: IDVLayout.Size.heroCircle, height: IDVLayout.Size.heroCircle)
                Image(systemName: IDVIcon.faceMismatchBadge)
                    .font(.system(size: IDVLayout.IconSize.hero))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.error)
            }

            VStack(spacing: IDVLayout.Spacing.title) {
                Text(IDVStrings.FaceCapture.failTitle, bundle: .module)
                    .font(theme.font(.largeTitle))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(verbatim: message)
                    .font(theme.font(.body))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, theme.screenPadding)

            Spacer()

            Button(action: model.retry) {
                Text(IDVStrings.Button.tryAgain, bundle: .module)
                    .font(theme.font(.button)).foregroundStyle(theme.onPrimary)
                    .frame(maxWidth: .infinity, minHeight: IDVLayout.Size.buttonHeight)
                    .background(theme.primary, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            }
            Button(action: model.cancel) {
                Text(IDVStrings.Button.cancel, bundle: .module)
                    .font(theme.font(.button)).foregroundStyle(theme.textSecondary)
            }
        }
        .padding(theme.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }
}

// MARK: - Oval state

extension IDVFaceCaptureView {
    enum OvalState { case idle, adjusting, active, success, error }

    enum FaceStep: Equatable {
        case tutorial
        case positioning
        case challenge(index: Int)
        case transition
        case headRotation
        case neutralPose
        case capturing
        case processing
        case success
        case failed(String)
    }

    /// The liveness + face-match state machine. Ported from the Votari flow onto
    /// IDVKit's ``IDVLivenessSession`` / ``IDVFaceMatcher``, with the same
    /// grace-period pauses (1.5s to read a challenge, 0.5s green pulse between
    /// challenges, 1.5s neutral settle, 0.3s capture flash).
    @MainActor
    final class Model: ObservableObject {
        // Starts on `.tutorial` so the camera/AR view is never mounted before
        // `start()` runs on appear and decides the route (showing the tutorial, or
        // going straight to positioning when the tutorial is disabled). This also
        // prevents a first-frame race where the AR view reports "unsupported"
        // before `start()` has a chance to route.
        @Published var step: FaceStep = .tutorial
        @Published var instruction: LocalizedStringKey = IDVStrings.FaceCapture.positionFace
        @Published var completedCount = 0
        @Published var timeoutProgress: CGFloat = 1
        @Published var captureRequested = false
        @Published var sessionPaused = false
        @Published var ovalState: OvalState = .idle
        @Published var challengeIcon: String?
        @Published var showPulse = false
        @Published var isLowLight = false
        @Published private(set) var multipleFaces = false
        /// Lit segments for the head-rotation ring (mirrors the session tracker).
        @Published var ringFilled: [Bool] = []

        /// Set by the view before ``start()``. When the user has Reduce Motion on,
        /// the head-rotation phase is skipped for a steady frontal hold.
        var prefersReducedMotion = false

        var challenges: [IDVLivenessChallenge] {
            session.challenges
        }

        /// The live camera HUD is hidden while a full-screen overlay is up.
        var showsHUD: Bool {
            switch step {
            case .tutorial, .processing, .success, .failed: false
            default: true
            }
        }

        /// The "step N of M" dots only make sense during the active-challenge
        /// phase — not during positioning, head rotation, or capture.
        var showsChallengeDots: Bool {
            switch step {
            case .challenge, .transition: challenges.count > 1
            default: false
            }
        }

        /// The soft Siri glow shows whenever the camera is live and framing the face.
        var showsGlow: Bool {
            switch step {
            case .positioning, .challenge, .transition, .headRotation, .neutralPose, .capturing: true
            default: false
            }
        }

        /// Once the head-rotation ring has been filled, keep showing it (fully green)
        /// through the neutral-pose capture so the user still sees their completed
        /// progress while looking at the camera.
        var showsRing: Bool {
            guard !ringFilled.isEmpty else { return false }
            return switch step {
            case .headRotation, .transition, .neutralPose, .capturing: true
            default: false
            }
        }

        private let reference: CGImage
        private let configuration: IDVFaceConfiguration
        private let session: IDVLivenessSession
        private let matcher: IDVFaceMatcher
        private let onComplete: (IDVLivenessOutcome, IDVFaceMatchResult) -> Void
        private let onCancelHandler: () -> Void

        private var capturedSelfie: CGImage?
        /// How many times the user has retried this capture. After
        /// ``IDVFaceConfiguration/maxRetries`` the next retry restarts the whole
        /// check (re-showing the tutorial) rather than looping the same attempt.
        private var retryCount = 0
        private var challengeStart: Date?
        private var neutralStart: Date?
        private var positioningStart: Date?
        private var lastLightWarning: Date?
        private var challengeTimer: AnyCancellable?
        private var sessionTimer: AnyCancellable?
        private var sessionStart: Date?

        private let challengeGracePeriod: TimeInterval = IDVLayout.Duration.challengeGrace

        private let debugDesignPreview: Bool
        private var designTimer: AnyCancellable?

        init(reference: CGImage, configuration: IDVFaceConfiguration,
             onComplete: @escaping (IDVLivenessOutcome, IDVFaceMatchResult) -> Void,
             onCancel: @escaping () -> Void,
             debugDesignPreview: Bool = false) {
            self.reference = reference
            self.configuration = configuration
            session = IDVLivenessSession(configuration: configuration)
            matcher = IDVFaceMatcher(configuration: configuration)
            self.onComplete = onComplete
            onCancelHandler = onCancel
            self.debugDesignPreview = debugDesignPreview
        }

        // MARK: Lifecycle

        func start() {
            // A fresh start is a clean slate: reset the liveness retry budget so a
            // reused Model (should the flow ever re-enter) never carries a stale
            // count. Today Model is a @StateObject recreated per appearance, but the
            // invariant shouldn't depend on that.
            retryCount = 0
            #if DEBUG
                if debugDesignPreview {
                    startDesignPreview()
                    return
                }
            #endif
            // Show the coaching tutorial first (if enabled); the camera warms up
            // behind it. Otherwise go straight into positioning.
            if configuration.showsTutorial {
                step = .tutorial
                return
            }
            beginLiveness()
        }

        #if DEBUG
            /// Drives the head-rotation ring on a timer (no camera) so the capture
            /// design can be reviewed in the Simulator.
            private func startDesignPreview() {
                step = .headRotation
                ovalState = .active
                instruction = IDVStrings.FaceCapture.rotateHead
                let total = session.headRotation.segmentCount
                var lit = 0
                designTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
                    .sink { [weak self] _ in
                        guard let self else { return }
                        lit = (lit + 1) % (total + 12) // fill, brief pause, loop
                        ringFilled = (0 ..< total).map { $0 < lit }
                    }
            }
        #endif

        /// Begins the live capture after the tutorial (or immediately when the
        /// tutorial is disabled).
        func beginLiveness() {
            startSessionTimer()
            step = .positioning
            ovalState = .idle
            positioningStart = nil
            multipleFaces = false
            instruction = IDVStrings.FaceCapture.positionFace
            Logger.face.idvDebug("Liveness: started, mode=\(configuration.livenessMode.rawValue), challenges=\(session.challenges.map(\.rawValue))")
        }

        func stop() {
            challengeTimer?.cancel()
            sessionTimer?.cancel()
            designTimer?.cancel()
        }

        func cancel() {
            stop()
            sessionPaused = true
            onCancelHandler()
        }

        func retry() {
            session.reset()
            completedCount = 0
            capturedSelfie = nil
            sessionPaused = false
            challengeIcon = nil
            ringFilled = []
            challengeTimer?.cancel()
            retryCount += 1
            let maxRetries = matcher.configuration.maxRetries
            if retryCount > maxRetries {
                // Too many failures in a row — restart the whole check from the top
                // (re-showing the tutorial) for a clean fresh run.
                Logger.face.idvDebug("Liveness: retry limit (\(maxRetries)) reached → full restart")
                retryCount = 0
                start()
            } else {
                // A normal retry skips the tutorial — the user has already seen it.
                Logger.face.idvDebug("Liveness: retry \(retryCount)/\(maxRetries)")
                beginLiveness()
            }
        }

        func handleFaceLost() { /* keep last guidance; positioning re-evaluates on next frame */ }

        func handleUnsupported() {
            fail(IDVStrings.FaceCapture.Failure.unsupportedDevice)
        }

        func handleLight(_ intensity: CGFloat) {
            if intensity < IDVLayout.Light.low {
                isLowLight = true
            } else if intensity > IDVLayout.Light.normal {
                isLowLight = false
            }
        }

        /// A second face in view blocks progress until only one remains.
        func handleFaceCount(_ count: Int) {
            let multiple = count > 1
            guard multiple != multipleFaces else { return }
            multipleFaces = multiple
            Logger.face.idvDebug("Liveness: face count = \(count)\(multiple ? " → blocking (multiple faces)" : " → resumed")")
            if multiple {
                ovalState = .adjusting
                challengeTimer?.cancel() // pause: don't fail a challenge on timeout while blocked
            } else {
                ovalState = .idle
                // Resume the current step with fresh grace, so a transient second
                // face never fails the whole attempt.
                if case .challenge = step {
                    challengeStart = Date()
                    startChallengeTimer()
                } else if step == .positioning {
                    positioningStart = Date()
                }
            }
        }

        // MARK: Frame dispatch

        func handleFrame(_ frame: IDVFaceFrame) {
            guard !multipleFaces else { return } // hold while a 2nd face is present
            switch step {
            case .positioning: positioning(frame)
            case let .challenge(index): challengeUpdate(frame, index: index)
            case .headRotation: headRotationUpdate(frame)
            case .neutralPose: neutralUpdate(frame)
            default: break
            }
        }

        private func positioning(_ frame: IDVFaceFrame) {
            if positioningStart == nil {
                positioningStart = Date()
            }
            updatePositioningCoaching(frame)
            // No head-angle gate here: the oval frames the user and the phases
            // themselves prove head control, so we just collect anti-spoof samples
            // (natural micro-sway) and advance.
            session.recordPositioningSample(yaw: frame.yaw)
            let elapsed = positioningStart.map { Date().timeIntervalSince($0) } ?? 0
            if session.hasPassedMicroMovementCheck || elapsed > IDVLayout.Duration.positioningTimeout {
                advanceFromPositioning()
            }
        }

        /// Distance-only coaching while positioning (too far / too close). The
        /// thresholds are in raw ARKit metres and should be device-tuned.
        private func updatePositioningCoaching(_ frame: IDVFaceFrame) {
            let next: LocalizedStringKey = if frame.distance > IDVLayout.Distance.tooFar {
                IDVStrings.FaceCapture.moveCloser
            } else if frame.distance < IDVLayout.Distance.tooClose {
                IDVStrings.FaceCapture.moveBack
            } else {
                IDVStrings.FaceCapture.positionFace
            }
            if instruction != next {
                instruction = next
            }
        }

        /// Routes out of positioning into the first phase for the configured mode.
        private func advanceFromPositioning() {
            let mode = configuration.livenessMode
            if mode.usesActiveChallenges {
                startFirstChallenge()
            } else if mode.usesHeadRotation {
                startHeadRotation()
            } else {
                startNeutralPose()
            }
        }

        // MARK: Challenges

        private func startFirstChallenge() {
            guard let challenge = session.currentChallenge else { return startNeutralPose() }
            completedCount = 0
            ovalState = .active
            challengeIcon = challenge.iconName
            instruction = challenge.instruction
            challengeStart = Date()
            step = .challenge(index: 0)
            startChallengeTimer()
            impact(.light)
            Logger.face.idvDebug("Liveness: challenge 1/\(session.challenges.count) = \(challenge.rawValue)")
        }

        private func challengeUpdate(_ frame: IDVFaceFrame, index: Int) {
            guard let challenge = session.currentChallenge else { return }
            if let start = challengeStart, Date().timeIntervalSince(start) < challengeGracePeriod {
                return
            }
            guard IDVLivenessSession.evaluate(challenge, frame: frame) else { return }

            challengeTimer?.cancel()
            step = .transition
            completedCount = index + 1
            ovalState = .success
            showPulse = true
            notify(.success)

            DispatchQueue.main.asyncAfter(deadline: .now() + IDVLayout.Duration.challengeTransition) { [weak self] in
                guard let self else { return }
                showPulse = false
                if session.advance(), let next = session.currentChallenge {
                    ovalState = .active
                    challengeIcon = next.iconName
                    instruction = next.instruction
                    challengeStart = Date()
                    step = .challenge(index: index + 1)
                    startChallengeTimer()
                } else {
                    // Active challenges done — the ring phase follows in `.both`.
                    challengeIcon = nil
                    if configuration.livenessMode.usesHeadRotation {
                        startHeadRotation()
                    } else {
                        startNeutralPose()
                    }
                }
            }
        }

        // MARK: Head-rotation ring

        private func startHeadRotation() {
            // Reduce Motion (or an unsupported preference): skip the rotation and
            // capture from a steady frontal hold, like Face ID's Accessibility
            // Options.
            guard !prefersReducedMotion else { return startNeutralPose() }
            session.headRotation.reset()
            ringFilled = session.headRotation.filledSegments
            step = .headRotation
            ovalState = .active
            instruction = IDVStrings.FaceCapture.rotateHead
            impact(.light)
            startHeadRotationFallback()
            Logger.face.idvDebug("Liveness: head-rotation phase (\(session.headRotation.segmentCount) segments)")
        }

        private func headRotationUpdate(_ frame: IDVFaceFrame) {
            if session.headRotation.record(directionX: frame.directionX, directionY: frame.directionY) {
                ringFilled = session.headRotation.filledSegments
                impact(.light) // per-arc haptic tick as new ticks latch
                if session.headRotation.progress > 0.5, instruction != IDVStrings.FaceCapture.keepGoing {
                    instruction = IDVStrings.FaceCapture.keepGoing
                }
            }
            if session.headRotation.isComplete {
                finishHeadRotation()
            }
        }

        private func finishHeadRotation() {
            guard step == .headRotation else { return }
            step = .transition
            ovalState = .success
            // Fill the whole ring green and hold it, so the user sees completion
            // before the prompt changes to "look at the camera".
            ringFilled = Array(repeating: true, count: session.headRotation.segmentCount)
            showPulse = true
            notify(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + IDVLayout.Duration.ringCompletePause) { [weak self] in
                guard let self else { return }
                showPulse = false
                startNeutralPose()
            }
        }

        /// If the ring is never completed (e.g. the user can't rotate far enough),
        /// fall through to a steady-hold capture so no one is ever stuck.
        private func startHeadRotationFallback() {
            DispatchQueue.main.asyncAfter(deadline: .now() + IDVLayout.Duration.headRotationTimeout) { [weak self] in
                guard let self, step == .headRotation else { return }
                Logger.face.idvDebug("Liveness: head-rotation fallback → capture")
                startNeutralPose()
            }
        }

        /// Accessibility escape hatch: abandon the ring and capture from a steady
        /// frontal hold instead.
        func skipHeadRotation() {
            guard step == .headRotation else { return }
            Logger.face.idvDebug("Liveness: head-rotation skipped by user")
            startNeutralPose()
        }

        // MARK: Neutral pose → capture

        private func startNeutralPose() {
            step = .neutralPose
            ovalState = .active
            instruction = IDVStrings.FaceCapture.lookStraight
            neutralStart = Date()
            impact(.light)
            // Fallback: capture even if the pose isn't perfectly neutral.
            DispatchQueue.main.asyncAfter(deadline: .now() + IDVLayout.Duration.neutralPoseFallback) { [weak self] in
                guard let self, step == .neutralPose else { return }
                startCapture()
            }
        }

        private func neutralUpdate(_ frame: IDVFaceFrame) {
            guard let start = neutralStart, Date().timeIntervalSince(start) >= IDVLayout.Duration.neutralPoseSettle else { return }
            if IDVLivenessSession.isNeutralPose(frame: frame) {
                startCapture()
            }
        }

        private func startCapture() {
            guard step == .neutralPose else { return }
            step = .capturing
            instruction = IDVStrings.FaceCapture.holdStill
            DispatchQueue.main.asyncAfter(deadline: .now() + IDVLayout.Duration.captureFlashDelay) { [weak self] in
                guard let self, step == .capturing else { return }
                captureRequested = true
            }
        }

        func handleCapture(_ image: CGImage) {
            guard step == .capturing else { return }
            capturedSelfie = image
            performMatch(selfie: image)
        }

        // MARK: Matching

        private func performMatch(selfie: CGImage) {
            step = .processing
            challengeTimer?.cancel()
            sessionTimer?.cancel()
            Task { @MainActor in
                await Task.yield() // let the "Verifying…" overlay paint before inference
                do {
                    let result = try matcher.match(reference: reference, live: selfie)
                    if result.isMatch {
                        ovalState = .success
                        step = .success
                        notify(.success)
                        let liveness = IDVLivenessOutcome(
                            passed: true,
                            challengesCompleted: session.completedChallengeNames,
                            capturedImageData: selfie.idvJPEGData()
                        )
                        // Hold the green checkmark briefly, then hand back.
                        DispatchQueue.main.asyncAfter(deadline: .now() + IDVLayout.Duration.successDwell) { [weak self] in
                            self?.onComplete(liveness, result)
                        }
                    } else {
                        fail(IDVStrings.FaceCapture.Failure.faceMismatch)
                    }
                } catch let error as IDVError {
                    switch error {
                    case .noFaceDetected: fail(IDVStrings.FaceCapture.Failure.noFaceDetected)
                    case .multipleFacesDetected: fail(IDVStrings.FaceCapture.Failure.multipleFaces)
                    default: fail(error.errorDescription ?? IDVStrings.FaceCapture.Failure.generic)
                    }
                } catch {
                    fail(IDVStrings.FaceCapture.Failure.generic)
                }
            }
        }

        private func fail(_ message: String) {
            challengeTimer?.cancel()
            sessionTimer?.cancel()
            ovalState = .error
            notify(.error)
            step = .failed(message)
            Logger.face.idvError("Liveness failed: \(message)")
        }

        // MARK: Timers

        private func startChallengeTimer() {
            timeoutProgress = 1
            let interval = IDVLayout.Duration.timerTick
            let decrement = CGFloat(interval / configurationTimeout)
            challengeTimer = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    timeoutProgress -= decrement
                    if timeoutProgress <= 0 {
                        challengeTimer?.cancel()
                        fail(IDVStrings.FaceCapture.Failure.challengeTimeout)
                    }
                }
        }

        private func startSessionTimer() {
            sessionStart = Date()
            sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in
                    guard let self, let start = sessionStart else { return }
                    if Date().timeIntervalSince(start) >= sessionTimeout {
                        sessionTimer?.cancel()
                        fail(IDVStrings.FaceCapture.Failure.sessionTimeout)
                    }
                }
        }

        private var configurationTimeout: TimeInterval {
            matcher.configuration.challengeTimeout
        }

        private var sessionTimeout: TimeInterval {
            matcher.configuration.sessionTimeout
        }

        // MARK: Haptics

        private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
            UINotificationFeedbackGenerator().notificationOccurred(type)
        }

        private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }
}

// MARK: - Challenge presentation

extension IDVLivenessChallenge {
    var instruction: LocalizedStringKey {
        switch self {
        case .blinkLeft: IDVStrings.Challenge.blinkLeft
        case .blinkRight: IDVStrings.Challenge.blinkRight
        case .smile: IDVStrings.Challenge.smile
        case .openMouth: IDVStrings.Challenge.openMouth
        case .turnLeft: IDVStrings.Challenge.turnLeft
        case .turnRight: IDVStrings.Challenge.turnRight
        }
    }

    var iconName: String {
        switch self {
        case .blinkLeft, .blinkRight: IDVIcon.Challenge.blink
        case .smile: IDVIcon.Challenge.smile
        case .openMouth: IDVIcon.Challenge.openMouth
        case .turnLeft: IDVIcon.Challenge.turnLeft
        case .turnRight: IDVIcon.Challenge.turnRight
        }
    }
}
