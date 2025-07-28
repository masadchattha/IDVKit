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
                    .stroke(ovalColor, style: .init(lineWidth: 4, lineCap: .round))
                    .frame(width: oval.width, height: oval.height)
                    .position(x: oval.midX, y: oval.midY)
                    .scaleEffect(model.showPulse ? 1.04 : 1.0)
                    .animation(.easeOut(duration: 0.25), value: model.showPulse)
                    .animation(.easeInOut(duration: 0.3), value: model.ovalState)

                chrome(oval: oval, safeArea: realSafeAreaInsets)

                if model.step == .processing { processingOverlay }
                if case .failed(let message) = model.step { failureOverlay(message) }
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
    private var realSafeAreaInsets: EdgeInsets { .vidKeyWindowSafeArea }

    private func ovalRect(in size: CGSize) -> CGRect {
        let width = min(size.width - 80, 300)
        let height = width * 1.3
        return CGRect(x: (size.width - width) / 2, y: size.height * 0.4 - height / 2, width: width, height: height)
    }

    private var ovalColor: Color {
        switch model.ovalState {
        case .idle: .white.opacity(0.4)
        case .adjusting: theme.warning
        case .active: .white
        case .success: theme.success
        case .error: theme.error
        }
    }

    // MARK: Chrome

    @ViewBuilder
    private func chrome(oval: CGRect, safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: model.cancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            }
            .padding(.horizontal, theme.screenPadding)
            .padding(.top, max(safeArea.top, 12))

            // One banner at a time; a second face is the more urgent warning.
            Group {
                if model.multipleFaces {
                    warningBanner("Only one face should be visible", systemImage: "person.2.slash.fill")
                } else if model.isLowLight {
                    lowLightBanner
                }
            }
            .padding(.top, 12)
            .animation(.easeInOut(duration: 0.2), value: model.multipleFaces)
            .animation(.easeInOut(duration: 0.2), value: model.isLowLight)

            Spacer()

            // Bottom HUD — hidden while a processing/failure overlay is shown so
            // stale prompts (e.g. "Hold still…") never bleed through.
            if model.showsHUD {
                VStack(spacing: 16) {
                    if model.challenges.count > 1 { challengeProgress }

                    // Fixed-height icon slot so the text below never jumps when the
                    // icon appears/disappears between a challenge and the neutral pose.
                    ZStack {
                        if let icon = model.challengeIcon {
                            Image(systemName: icon)
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                                .id(icon)
                        }
                    }
                    .frame(height: 46)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.challengeIcon)

                    Text(model.instruction)
                        .font(theme.font(.title))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, theme.screenPadding)
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: model.instruction)
                }
                .padding(.bottom, max(safeArea.bottom, 16) + 28)
                .transition(.opacity)
            }
        }
    }

    /// "Step N of M" progress for the challenge sequence, shown above the prompt.
    private var challengeProgress: some View {
        HStack(spacing: 8) {
            ForEach(model.challenges.indices, id: \.self) { index in
                Capsule()
                    .fill(index < model.completedCount ? theme.success : Color.white.opacity(0.3))
                    .frame(width: index < model.completedCount ? 22 : 14, height: 5)
                    .animation(.easeInOut, value: model.completedCount)
            }
        }
    }

    private var lowLightBanner: some View {
        Label {
            Text("Move to a brighter area", bundle: .module)
        } icon: {
            Image(systemName: "lightbulb.slash.fill")
        }
        .font(theme.font(.caption))
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
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
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.warning, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Verifying…", bundle: .module)
                    .font(theme.font(.headline)).foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private func failureOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: theme.screenPadding) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle).foregroundStyle(theme.error)
                Text(verbatim: message)
                    .font(theme.font(.title)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(.horizontal, theme.screenPadding)
                Button(action: model.retry) {
                    Text("Try again", bundle: .module)
                        .font(theme.font(.button)).foregroundStyle(theme.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(theme.primary, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                }
                Button(action: model.cancel) {
                    Text("Cancel", bundle: .module).font(theme.font(.button)).foregroundStyle(.white.opacity(0.8))
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
        @Published var instruction: LocalizedStringKey = "Position your face in the oval"
        @Published var completedCount = 0
        @Published var timeoutProgress: CGFloat = 1
        @Published var captureRequested = false
        @Published var sessionPaused = false
        @Published var ovalState: OvalState = .idle
        @Published var challengeIcon: String?
        @Published var showPulse = false
        @Published var isLowLight = false
        @Published private(set) var multipleFaces = false

        var challenges: [VIDLivenessChallenge] { session.challenges }
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

        private let challengeGracePeriod: TimeInterval = 1.5

        init(reference: CGImage, configuration: VIDFaceConfiguration,
             onComplete: @escaping (VIDLivenessOutcome, VIDFaceMatchResult) -> Void,
             onCancel: @escaping () -> Void) {
            self.reference = reference
            self.session = VIDLivenessSession(configuration: configuration)
            self.matcher = VIDFaceMatcher(configuration: configuration)
            self.onComplete = onComplete
            self.onCancelHandler = onCancel
        }

        // MARK: Lifecycle

        func start() {
            startSessionTimer()
            step = .positioning
            ovalState = .idle
            positioningStart = nil
            multipleFaces = false
            instruction = "Position your face in the oval"
            Logger.face.vidDebug("Liveness: started, challenges=\(self.session.challenges.map(\.rawValue))")
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
            instruction = "Position your face in the oval"
            Logger.face.vidDebug("Liveness: retry")
        }

        func handleFaceLost() { /* keep last guidance; positioning re-evaluates on next frame */ }

        func handleUnsupported() {
            fail("Face scanning needs a device with Face ID (TrueDepth camera).")
        }

        func handleLight(_ intensity: CGFloat) {
            if intensity < 200 { isLowLight = true }
            else if intensity > 350 { isLowLight = false }
        }

        /// A second face in view blocks progress until only one remains.
        func handleFaceCount(_ count: Int) {
            let multiple = count > 1
            guard multiple != multipleFaces else { return }
            multipleFaces = multiple
            Logger.face.vidDebug("Liveness: face count = \(count)\(multiple ? " → blocking (multiple faces)" : " → resumed")")
            if multiple {
                ovalState = .adjusting
                challengeTimer?.cancel()  // pause: don't fail a challenge on timeout while blocked
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
            guard !multipleFaces else { return }  // hold while a 2nd face is present
            switch step {
            case .positioning: positioning(frame)
            case .challenge(let index): challengeUpdate(frame, index: index)
            case .neutralPose: neutralUpdate(frame)
            default: break
            }
        }

        private func positioning(_ frame: VIDFaceFrame) {
            if positioningStart == nil { positioningStart = Date() }
            // No head-angle guidance: the ARKit yaw/pitch are unreliable here and
            // false-flag a frontal face ("Turn to face the camera"). The oval frames
            // the user and the challenges themselves prove head control, so we just
            // collect anti-spoof samples and advance.
            session.recordPositioningSample(yaw: frame.yaw)
            let elapsed = positioningStart.map { Date().timeIntervalSince($0) } ?? 0
            if session.hasPassedMicroMovementCheck || elapsed > 2.5 {
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
            Logger.face.vidDebug("Liveness: challenge 1/\(self.session.challenges.count) = \(challenge.rawValue)")
        }

        private func challengeUpdate(_ frame: VIDFaceFrame, index: Int) {
            guard let challenge = session.currentChallenge else { return }
            if let start = challengeStart, Date().timeIntervalSince(start) < challengeGracePeriod { return }
            guard VIDLivenessSession.evaluate(challenge, frame: frame) else { return }

            challengeTimer?.cancel()
            step = .transition
            completedCount = index + 1
            ovalState = .success
            showPulse = true
            notify(.success)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.showPulse = false
                if self.session.advance(), let next = self.session.currentChallenge {
                    self.ovalState = .active
                    self.challengeIcon = next.iconName
                    self.instruction = next.instruction
                    self.challengeStart = Date()
                    self.step = .challenge(index: index + 1)
                    self.startChallengeTimer()
                } else {
                    self.challengeIcon = nil
                    self.startNeutralPose()
                }
            }
        }

        // MARK: Neutral pose → capture

        private func startNeutralPose() {
            step = .neutralPose
            ovalState = .active
            instruction = "Look straight at the camera"
            neutralStart = Date()
            impact(.light)
            // Fallback: capture after 3s even if the pose isn't perfectly neutral.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self, self.step == .neutralPose else { return }
                self.startCapture()
            }
        }

        private func neutralUpdate(_ frame: VIDFaceFrame) {
            guard let start = neutralStart, Date().timeIntervalSince(start) >= 1.5 else { return }
            if VIDLivenessSession.isNeutralPose(frame: frame) { startCapture() }
        }

        private func startCapture() {
            guard step == .neutralPose else { return }
            step = .capturing
            instruction = "Hold still…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.step == .capturing else { return }
                self.captureRequested = true
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
                await Task.yield()  // let the "Verifying…" overlay paint before inference
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
                        fail("Your face didn't match the document photo.")
                    }
                } catch let error as VIDError {
                    switch error {
                    case .noFaceDetected: fail("We couldn't see your face clearly. Try again.")
                    case .multipleFacesDetected: fail("More than one face was in view. Make sure you're the only person visible.")
                    default: fail(error.errorDescription ?? "Verification failed. Please try again.")
                    }
                } catch {
                    fail("Verification failed. Please try again.")
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
            let interval: TimeInterval = 0.05
            let decrement = CGFloat(interval / configurationTimeout)
            challengeTimer = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.timeoutProgress -= decrement
                    if self.timeoutProgress <= 0 {
                        self.challengeTimer?.cancel()
                        self.fail("Challenge timed out. Try again.")
                    }
                }
        }

        private func startSessionTimer() {
            sessionStart = Date()
            sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in
                    guard let self, let start = self.sessionStart else { return }
                    if Date().timeIntervalSince(start) >= self.sessionTimeout {
                        self.sessionTimer?.cancel()
                        self.fail("Session timed out. Please try again.")
                    }
                }
        }

        private var configurationTimeout: TimeInterval { matcher.configuration.challengeTimeout }
        private var sessionTimeout: TimeInterval { matcher.configuration.sessionTimeout }

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
        case .blinkLeft: "Blink your left eye"
        case .blinkRight: "Blink your right eye"
        case .smile: "Smile"
        case .openMouth: "Open your mouth"
        case .turnLeft: "Turn your head left"
        case .turnRight: "Turn your head right"
        }
    }

    var iconName: String {
        switch self {
        case .blinkLeft, .blinkRight: "eye"
        case .smile: "face.smiling"
        case .openMouth: "mouth"
        case .turnLeft: "arrow.left"
        case .turnRight: "arrow.right"
        }
    }
}
