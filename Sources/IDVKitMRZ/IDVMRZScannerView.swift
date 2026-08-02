//
//  IDVMRZScannerView.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import AVFoundation
import SwiftUI
import UIKit
import IDVKitCore

/// Drop-in MRZ scanning screen: live camera feed under a dimmed scrim with a
/// passport-shaped cutout, highlighted MRZ strip, animated scan line, corner
/// brackets, torch toggle and guidance text. Fully themeable via `.idvTheme(_:)`.
///
/// ```swift
/// IDVMRZScannerView { mrz in
///     print(mrz.documentNumber)
/// } onError: { error in ... }
/// ```
public struct IDVMRZScannerView: View {
    private let configuration: IDVMRZConfiguration
    private let onResult: (IDVMRZData) -> Void
    private let onError: (IDVError) -> Void
    private let onClose: (() -> Void)?

    @Environment(\.idvTheme) private var theme
    @State private var scanner = IDVMRZScanner()
    @State private var scanLinePhase = false
    @State private var torchOn = false
    @State private var didSucceed = false

    /// - Parameter onClose: when provided, a close (✕) button is shown in the
    ///   top corner. Omit it if you present your own dismissal chrome.
    public init(
        configuration: IDVMRZConfiguration = .init(),
        onResult: @escaping (IDVMRZData) -> Void,
        onError: @escaping (IDVError) -> Void = { _ in },
        onClose: (() -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onResult = onResult
        self.onError = onError
        self.onClose = onClose
    }

    public var body: some View {
        // The GeometryReader ignores the safe area so its coordinate space
        // matches the full-bleed camera and scrim beneath it. Without this the
        // dimming overlay stops short of the home-indicator strip when the view
        // is presented inside a sheet, leaving an undimmed band at the bottom.
        GeometryReader { geometry in
            let guide = documentGuideRect(in: geometry.size)
            let mrzStrip = mrzStripRect(inGuide: guide)

            ZStack {
                CameraPreview(scanner: scanner)

                // Dimmed scrim with a see-through document window.
                theme.overlayScrim
                    .mask {
                        Rectangle()
                            .overlay(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: theme.cornerRadius)
                                    .frame(width: guide.width, height: guide.height)
                                    .offset(x: guide.minX, y: guide.minY)
                                    .blendMode(.destinationOut)
                            }
                    }

                cornerBrackets(around: guide)

                // MRZ strip highlight + animated scan line.
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.captureGuide.opacity(0.9), lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.captureGuide.opacity(0.08))
                    )
                    .frame(width: mrzStrip.width, height: mrzStrip.height)
                    .position(x: mrzStrip.midX, y: mrzStrip.midY)

                scanLine(in: mrzStrip)

                overlayChrome(guide: guide, safeArea: realSafeAreaInsets)

                if let onClose {
                    closeButton(onClose, topInset: realSafeAreaInsets.top)
                }
            }
            .onAppear {
                scanner.onResult = { mrz in
                    guard !didSucceed else { return }
                    didSucceed = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    scanner.stop()
                    onResult(mrz)
                }
                scanner.onError = { onError($0) }
                scanner.start()
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    scanLinePhase = true
                }
            }
            .onDisappear { scanner.stop() }
        }
        .ignoresSafeArea()
        .background(Color.black)
    }

    // MARK: Layout

    /// The window's true safe-area insets — the `GeometryReader` ignores the safe
    /// area (so the scrim matches the full-bleed camera), which zeroes its proxy.
    private var realSafeAreaInsets: EdgeInsets {
        .idvKeyWindowSafeArea
    }

    /// Guide width ÷ height for the configured document. A passport data page is
    /// ≈1.42:1; an ID-1 card is ≈1.585:1; `.any` uses a neutral shape that suits
    /// both (recognition auto-detects the real layout regardless).
    private var documentAspect: CGFloat {
        switch configuration.documentKind {
        case .passport: 1.42
        case .idCard, .residencePermit: 1.585
        case .any: 1.5
        }
    }

    /// Fraction of the guide height the MRZ band occupies at the bottom. TD3 has
    /// two lines (~22%); TD1 ID cards have three, so we reserve more for those.
    private var mrzStripFraction: CGFloat {
        switch configuration.documentKind {
        case .passport: 0.22
        case .idCard, .residencePermit, .any: 0.30
        }
    }

    /// Document-shaped guide, centered slightly above the middle of the screen.
    private func documentGuideRect(in size: CGSize) -> CGRect {
        let width = min(size.width - 48, 480)
        let height = width / documentAspect
        return CGRect(
            x: (size.width - width) / 2,
            y: size.height * 0.42 - height / 2,
            width: width,
            height: height
        )
    }

    /// The MRZ band at the bottom of the document.
    private func mrzStripRect(inGuide guide: CGRect) -> CGRect {
        let height = guide.height * mrzStripFraction
        return CGRect(
            x: guide.minX + 8,
            y: guide.maxY - height - 8,
            width: guide.width - 16,
            height: height
        )
    }

    // MARK: Overlay pieces

    private func scanLine(in strip: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: [theme.primary.opacity(0), theme.primary, theme.primary.opacity(0)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(width: strip.width - 8, height: 3)
            .shadow(color: theme.primary.opacity(0.8), radius: 6)
            .position(
                x: strip.midX,
                y: scanLinePhase ? strip.maxY - 6 : strip.minY + 6
            )
    }

    @ViewBuilder
    private func cornerBrackets(around rect: CGRect) -> some View {
        let length: CGFloat = 26
        let thickness: CGFloat = 4
        ForEach(0 ..< 4, id: \.self) { corner in
            BracketShape(length: length)
                .stroke(theme.captureGuide, style: .init(lineWidth: thickness, lineCap: .round))
                .frame(width: length, height: length)
                .rotationEffect(.degrees(Double(corner) * 90))
                .position(
                    x: corner == 0 || corner == 3 ? rect.minX + length / 2 - 6 : rect.maxX - length / 2 + 6,
                    y: corner <= 1 ? rect.minY + length / 2 - 6 : rect.maxY - length / 2 + 6
                )
        }
    }

    private func overlayChrome(guide: CGRect, safeArea: EdgeInsets) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Text("Scan your document", bundle: .module)
                    .font(theme.font(.title))
                    .foregroundStyle(.white)
                Text("Position your passport or ID inside the frame. The code lines at the bottom are read automatically.", bundle: .module)
                    .font(theme.font(.body))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, theme.screenPadding)
            .padding(.bottom, 28)

            if configuration.showsTorchButton {
                Button {
                    torchOn = scanner.toggleTorch()
                } label: {
                    Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.title2)
                        .foregroundStyle(torchOn ? Color.black : .white)
                        .frame(width: 54, height: 54)
                        .background(torchOn ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                }
                .accessibilityLabel(Text("Toggle flashlight", bundle: .module))
            }
        }
        // Keep chrome clear of the home indicator now that we fill the screen.
        .padding(.bottom, max(safeArea.bottom, 16) + 24)
    }

    private func closeButton(_ action: @escaping () -> Void, topInset: CGFloat) -> some View {
        VStack {
            HStack {
                Spacer()
                Button(action: action) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(theme.screenPadding)
                }
                .accessibilityLabel(Text("Close", bundle: .module))
            }
            Spacer()
        }
        .padding(.top, max(topInset, 12))
    }
}

/// One corner bracket ("L" shape), drawn for the top-leading corner.
private struct BracketShape: Shape {
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 8))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 8, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// UIKit bridge hosting the scanner's `AVCaptureVideoPreviewLayer`.
private struct CameraPreview: UIViewRepresentable {
    let scanner: IDVMRZScanner

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer = scanner.previewLayer
        view.layer.addSublayer(scanner.previewLayer)
        return view
    }

    func updateUIView(_ view: PreviewContainerView, context: Context) {}

    final class PreviewContainerView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
