//
//  VIDFaceCaptureView.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 12/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Combine
import CoreGraphics
import OSLog
import SwiftUI
import UIKit
import VerifIDCore
import VerifIDFace

/// Full-screen active-liveness capture: the user completes a couple of randomised
/// challenges (with brief grace-period pauses so each instruction is readable),
/// a neutral still is captured, and it's matched against the document portrait.
/// Clean, themed UI over ``VIDLivenessARView``.
public struct VIDFaceCaptureView: View {
    let reference: CGImage
    let configuration: VIDFaceConfiguration
    let onComplete: (VIDLivenessOutcome, VIDFaceMatchResult) -> Void
    let onCancel: () -> Void

    @Environment(\.vidTheme) private var theme
    @StateObject private var model: Model

    public init(
        reference: CGImage,
        configuration: VIDFaceConfiguration = .init(),
        onComplete: @escaping (VIDLivenessOutcome, VIDFaceMatchResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.reference = reference
        self.configuration = configuration
        self.onComplete = onComplete
        self.onCancel = onCancel
        _model = StateObject(wrappedValue: Model(reference: reference, configuration: configuration,
                                                 onComplete: onComplete, onCancel: onCancel))
    }

    public var body: some View {
        GeometryReader { geo in
            let oval = ovalRect(in: geo.size)
            ZStack {
                VIDLivenessARView(
                    onFrame: model.handleFrame,
                    onFaceLost: model.handleFaceLost,
                    onCapture: model.handleCapture,
                    onLightEstimate: model.handleLight,
                    onFaceCount: model.handleFaceCount,
                    onUnsupported: model.handleUnsupported,
                    captureRequested: $model.captureRequested,
                    sessionPaused: $model.sessionPaused
                )

                // Dim everything outside the face oval.
                theme.overlayScrim
                    .mask {
                        Rectangle()
                            .overlay(Ellipse().frame(width: oval.width, height: oval.height).position(x: oval.midX, y: oval.midY).blendMode(.destinationOut))
                    }

                Ellipse()
                    .stroke(ovalColor, style: .init(lineWidth: VIDLayout.Stroke.ovalGuide, lineCap: .round))
                    .frame(width: oval.width, height: oval.height)
                    .position(x: oval.midX, y: oval.midY)
                    .scaleEffect(model.showPulse ? VIDLayout.Scale.ovalPulse : 1.0)
                    .animation(.easeOut(duration: VIDLayout.Duration.ovalPulse), value: model.showPulse)
                    .animation(.easeInOut(duration: VIDLayout.Duration.ovalStateChange), value: model.ovalState)

                chrome(oval: oval, safeArea: realSafeAreaInsets)

                if model.step == .processing {
                    processingOverlay
                }
                if case let .failed(message) = model.step {
                    failureOverlay(message)
                }
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .onAppear(perform: model.start)
        .onDisappear(perform: model.stop)
    }

    // MARK: Layout

    /// The window's true safe-area insets (the `GeometryReader` ignores the safe
    /// area so the camera and overlays fill the screen, which zeroes its proxy).
    private var realSafeAreaInsets: EdgeInsets {
        .vidKeyWindowSafeArea
    }

    private func ovalRect(in size: CGSize) -> CGRect {
        let width = min(size.width - VIDLayout.Size.ovalHorizontalInset, VIDLayout.Size.ovalMaxWidth)
        let height = width * VIDLayout.Size.ovalAspectRatio
        return CGRect(
            x: (size.width - width) / 2,
            y: size.height * VIDLayout.Size.ovalVerticalPositionFactor - height / 2,
            width: width, height: height
        )
    }

    private var ovalColor: Color {
        switch model.ovalState {
        case .idle: .white.opacity(VIDLayout.Opacity.ovalIdle)
        case .adjusting: theme.warning
        case .active: .white
        case .success: theme.success
        case .error: theme.error
        }
    }

    // MARK: Chrome

    private func chrome(oval: CGRect, safeArea: EdgeInsets) -> some View {
        VStack(spacing: .zero) {
            HStack {
                Button(action: model.cancel) {
                    Image(systemName: VIDIcon.close)
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(VIDLayout.Opacity.chromeIcon))
                }
                Spacer()
            }
            .padding(.horizontal, theme.screenPadding)
            .padding(.top, max(safeArea.top, VIDLayout.Spacing.medium))

            // One banner at a time; a second face is the more urgent warning.
            Group {
                if model.multipleFaces {
                    warningBanner(VIDStrings.FaceCapture.multipleFacesWarning, systemImage: VIDIcon.multipleFaces)
                } else if model.isLowLight {
                    lowLightBanner
                }
            }
            .padding(.top, VIDLayout.Spacing.medium)
            .animation(.easeInOut(duration: VIDLayout.Duration.bannerToggle), value: model.multipleFaces)
            .animation(.easeInOut(duration: VIDLayout.Duration.bannerToggle), value: model.isLowLight)

            Spacer()

            // Bottom HUD — hidden while a processing/failure overlay is shown so
            // stale prompts (e.g. "Hold still…") never bleed through.
            if model.showsHUD {
                VStack(spacing: VIDLayout.Spacing.large) {
                    if model.challenges.count > 1 {
                        challengeProgress
                    }

                    // Fixed-height icon slot so the text below never jumps when the
                    // icon appears/disappears between a challenge and the neutral pose.
                    ZStack {
                        if let icon = model.challengeIcon {
                            Image(systemName: icon)
                                .font(.system(size: VIDLayout.IconSize.challenge, weight: .semibold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                                .id(icon)
                        }
                    }
                    .frame(height: VIDLayout.Size.challengeIconSlotHeight)
                    .animation(
                        .spring(response: VIDLayout.Spring.challengeIconResponse, dampingFraction: VIDLayout.Spring.challengeIconDamping),
                        value: model.challengeIcon
                    )

                    Text(model.instruction)
                        .font(theme.font(.title))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, theme.screenPadding)
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: model.instruction)
                }
                .padding(.bottom, max(safeArea.bottom, VIDLayout.Spacing.large) + VIDLayout.Spacing.hudBottomExtra)
                .transition(.opacity)
            }
        }
    }

    /// "Step N of M" progress for the challenge sequence, shown above the prompt.
    private var challengeProgress: some View {
        HStack(spacing: VIDLayout.Spacing.small) {
            ForEach(model.challenges.indices, id: \.self) { index in
                Capsule()
                    .fill(index < model.completedCount ? theme.success : Color.white.opacity(VIDLayout.Opacity.subtle))
                    .frame(
                        width: index < model.completedCount
                            ? VIDLayout.Size.challengeCapsuleActiveWidth
                            : VIDLayout.Size.challengeCapsuleInactiveWidth,
                        height: VIDLayout.Size.challengeCapsuleHeight
                    )
                    .animation(.easeInOut, value: model.completedCount)
            }
        }
    }

    private var lowLightBanner: some View {
        Label {
            Text(VIDStrings.FaceCapture.lowLightWarning, bundle: .module)
        } icon: {
            Image(systemName: VIDIcon.lowLight)
        }
        .font(theme.font(.caption))
        .foregroundStyle(.white)
        .padding(.horizontal, VIDLayout.Spacing.row).padding(.vertical, VIDLayout.Spacing.small)
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
        .padding(.horizontal, VIDLayout.Spacing.large).padding(.vertical, VIDLayout.Spacing.title)
        .background(theme.warning, in: Capsule())
        .shadow(color: .black.opacity(VIDLayout.Opacity.bannerShadow), radius: VIDLayout.Shadow.bannerRadius, y: VIDLayout.Shadow.bannerY)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(VIDLayout.Opacity.processingScrim).ignoresSafeArea()
            VStack(spacing: VIDLayout.Spacing.large) {
                ProgressView().controlSize(.large).tint(.white)
                Text(VIDStrings.FaceCapture.verifying, bundle: .module)
                    .font(theme.font(.headline)).foregroundStyle(.white)
            }
        }
    }

    private func failureOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(VIDLayout.Opacity.failureScrim).ignoresSafeArea()
            VStack(spacing: theme.screenPadding) {
                Image(systemName: VIDIcon.warning)
                    .font(.largeTitle).foregroundStyle(theme.error)
                Text(verbatim: message)
                    .font(theme.font(.title)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(.horizontal, theme.screenPadding)
                Button(action: model.retry) {
                    Text(VIDStrings.Button.tryAgain, bundle: .module)
                        .font(theme.font(.button)).foregroundStyle(theme.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: VIDLayout.Size.buttonHeight)
                        .background(theme.primary, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                }
                Button(action: model.cancel) {
                    Text(VIDStrings.Button.cancel, bundle: .module).font(theme.font(.button)).foregroundStyle(.white.opacity(VIDLayout.Opacity.mutedOnDark))
                }
            }
            .padding(theme.screenPadding)
        }
    }
}

// MARK: - Oval state

extension VIDFaceCaptureView {
    enum OvalState { case idle, adjusting, active, success, error }

    enum FaceStep: Equatable {
        case positioning
        case challenge(index: Int)
        case transition
        case neutralPose
        case capturing
        case processing
        case failed(String)
    }

    /// The liveness + face-match state machine. Ported from the Votari flow onto
    /// VerifID's ``VIDLivenessSession`` / ``VIDFaceMatcher``, with the same
    /// grace-period pauses (1.5s to read a challenge, 0.5s green pulse between
    /// challenges, 1.5s neutral settle, 0.3s capture flash).
    @MainActor
    final class Model: ObservableObject {
        @Published var step: FaceStep = .positioning
        @Published var instruction: LocalizedStringKey = VIDStrings.FaceCapture.positionFace
        @Published var completedCount = 0
        @Published var timeoutProgress: CGFloat = 1
        @Published var captureRequested = false
        @Published var sessionPaused = false
        @Published var ovalState: OvalState = .idle
        @Published var challengeIcon: String?
        @Published var showPulse = false
        @Published var isLowLight = false
        @Published private(set) var multipleFaces = false

        var challenges: [VIDLivenessChallenge] {
            session.challenges
        }

        /// The live camera HUD is hidden while a full-screen overlay is up.
        var showsHUD: Bool {
            switch step {
            case .processing, .failed: false
            default: true
            }
        }

        private let reference: CGImage
        private let session: VIDLivenessSession
        private let matcher: VIDFaceMatcher
        private let onComplete: (VIDLivenessOutcome, VIDFaceMatchResult) -> Void
        private let onCancelHandler: () -> Void

        private var capturedSelfie: CGImage?
        private var challengeStart: Date?
        private var neutralStart: Date?
        private var positioningStart: Date?
        private var lastLightWarning: Date?
        private var challengeTimer: AnyCancellable?
        private var sessionTimer: AnyCancellable?
        private var sessionStart: Date?

        private let challengeGracePeriod: TimeInterval = VIDLayout.Duration.challengeGrace

        init(reference: CGImage, configuration: VIDFaceConfiguration,
             onComplete: @escaping (VIDLivenessOutcome, VIDFaceMatchResult) -> Void,
             onCancel: @escaping () -> Void) {
            self.reference = reference
            session = VIDLivenessSession(configuration: configuration)
            matcher = VIDFaceMatcher(configuration: configuration)
            self.onComplete = onComplete
            onCancelHandler = onCancel
        }

        // MARK: Lifecycle

        func start() {
            startSessionTimer()
            step = .positioning
            ovalState = .idle
            positioningStart = nil
            multipleFaces = false
            instruction = VIDStrings.FaceCapture.positionFace
            Logger.face.vidDebug("Liveness: started, challenges=\(session.challenges.map(\.rawValue))")
        }

        func stop() {
            challengeTimer?.cancel()
            sessionTimer?.cancel()
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
            challengeTimer?.cancel()
            startSessionTimer()
            step = .positioning
            ovalState = .idle
            positioningStart = nil
            multipleFaces = false
            instruction = VIDStrings.FaceCapture.positionFace
            Logger.face.vidDebug("Liveness: retry")
        }

        func handleFaceLost() { /* keep last guidance; positioning re-evaluates on next frame */ }

        func handleUnsupported() {
            fail(VIDStrings.FaceCapture.Failure.unsupportedDevice)
        }

        func handleLight(_ intensity: CGFloat) {
            if intensity < VIDLayout.Light.low {
                isLowLight = true
            } else if intensity > VIDLayout.Light.normal {
                isLowLight = false
            }
        }

        /// A second face in view blocks progress until only one remains.
        func handleFaceCount(_ count: Int) {
            let multiple = count > 1
            guard multiple != multipleFaces else { return }
            multipleFaces = multiple
            Logger.face.vidDebug("Liveness: face count = \(count)\(multiple ? " → blocking (multiple faces)" : " → resumed")")
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

        func handleFrame(_ frame: VIDFaceFrame) {
            guard !multipleFaces else { return } // hold while a 2nd face is present
            switch step {
            case .positioning: positioning(frame)
            case let .challenge(index): challengeUpdate(frame, index: index)
            case .neutralPose: neutralUpdate(frame)
            default: break
            }
        }

        private func positioning(_ frame: VIDFaceFrame) {
            if positioningStart == nil {
                positioningStart = Date()
            }
            // No head-angle guidance: the ARKit yaw/pitch are unreliable here and
            // false-flag a frontal face ("Turn to face the camera"). The oval frames
            // the user and the challenges themselves prove head control, so we just
            // collect anti-spoof samples and advance.
            session.recordPositioningSample(yaw: frame.yaw)
            let elapsed = positioningStart.map { Date().timeIntervalSince($0) } ?? 0
            if session.hasPassedMicroMovementCheck || elapsed > VIDLayout.Duration.positioningTimeout {
                startFirstChallenge()
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
            Logger.face.vidDebug("Liveness: challenge 1/\(session.challenges.count) = \(challenge.rawValue)")
        }

        private func challengeUpdate(_ frame: VIDFaceFrame, index: Int) {
            guard let challenge = session.currentChallenge else { return }
            if let start = challengeStart, Date().timeIntervalSince(start) < challengeGracePeriod {
                return
            }
            guard VIDLivenessSession.evaluate(challenge, frame: frame) else { return }

            challengeTimer?.cancel()
            step = .transition
            completedCount = index + 1
            ovalState = .success
            showPulse = true
            notify(.success)

            DispatchQueue.main.asyncAfter(deadline: .now() + VIDLayout.Duration.challengeTransition) { [weak self] in
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
                    challengeIcon = nil
                    startNeutralPose()
                }
            }
        }

        // MARK: Neutral pose → capture

        private func startNeutralPose() {
            step = .neutralPose
            ovalState = .active
            instruction = VIDStrings.FaceCapture.lookStraight
            neutralStart = Date()
            impact(.light)
            // Fallback: capture even if the pose isn't perfectly neutral.
            DispatchQueue.main.asyncAfter(deadline: .now() + VIDLayout.Duration.neutralPoseFallback) { [weak self] in
                guard let self, step == .neutralPose else { return }
                startCapture()
            }
        }

        private func neutralUpdate(_ frame: VIDFaceFrame) {
            guard let start = neutralStart, Date().timeIntervalSince(start) >= VIDLayout.Duration.neutralPoseSettle else { return }
            if VIDLivenessSession.isNeutralPose(frame: frame) {
                startCapture()
            }
        }

        private func startCapture() {
            guard step == .neutralPose else { return }
            step = .capturing
            instruction = VIDStrings.FaceCapture.holdStill
            DispatchQueue.main.asyncAfter(deadline: .now() + VIDLayout.Duration.captureFlashDelay) { [weak self] in
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
                        notify(.success)
                        let liveness = VIDLivenessOutcome(
                            passed: true,
                            challengesCompleted: session.completedChallengeNames,
                            capturedImageData: selfie.vidJPEGData()
                        )
                        onComplete(liveness, result)
                    } else {
                        fail(VIDStrings.FaceCapture.Failure.faceMismatch)
                    }
                } catch let error as VIDError {
                    switch error {
                    case .noFaceDetected: fail(VIDStrings.FaceCapture.Failure.noFaceDetected)
                    case .multipleFacesDetected: fail(VIDStrings.FaceCapture.Failure.multipleFaces)
                    default: fail(error.errorDescription ?? VIDStrings.FaceCapture.Failure.generic)
                    }
                } catch {
                    fail(VIDStrings.FaceCapture.Failure.generic)
                }
            }
        }

        private func fail(_ message: String) {
            challengeTimer?.cancel()
            sessionTimer?.cancel()
            ovalState = .error
            notify(.error)
            step = .failed(message)
            Logger.face.vidError("Liveness failed: \(message)")
        }

        // MARK: Timers

        private func startChallengeTimer() {
            timeoutProgress = 1
            let interval = VIDLayout.Duration.timerTick
            let decrement = CGFloat(interval / configurationTimeout)
            challengeTimer = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    timeoutProgress -= decrement
                    if timeoutProgress <= 0 {
                        challengeTimer?.cancel()
                        fail(VIDStrings.FaceCapture.Failure.challengeTimeout)
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
                        fail(VIDStrings.FaceCapture.Failure.sessionTimeout)
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

extension VIDLivenessChallenge {
    var instruction: LocalizedStringKey {
        switch self {
        case .blinkLeft: VIDStrings.Challenge.blinkLeft
        case .blinkRight: VIDStrings.Challenge.blinkRight
        case .smile: VIDStrings.Challenge.smile
        case .openMouth: VIDStrings.Challenge.openMouth
        case .turnLeft: VIDStrings.Challenge.turnLeft
        case .turnRight: VIDStrings.Challenge.turnRight
        }
    }

    var iconName: String {
        switch self {
        case .blinkLeft, .blinkRight: VIDIcon.Challenge.blink
        case .smile: VIDIcon.Challenge.smile
        case .openMouth: VIDIcon.Challenge.openMouth
        case .turnLeft: VIDIcon.Challenge.turnLeft
        case .turnRight: VIDIcon.Challenge.turnRight
        }
    }
}
