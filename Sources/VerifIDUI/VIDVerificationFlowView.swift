//
//  VIDVerificationFlowView.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import PhotosUI
import SwiftUI
import VerifIDCore
import VerifIDFace
import VerifIDMRZ
import VerifIDNFC

/// The drop-in verification flow: **Intro → scan MRZ → read NFC chip → result**.
///
/// The flow reads the passport's machine-readable zone to derive the chip-access
/// key, opens the NFC chip (PACE or BAC), reads the data groups, runs passive
/// authentication, and shows a result. Face match/liveness is a later step.
/// Everything happens on-device. Themeable via `.vidTheme(_:)`, brandable via
/// ``VIDBrandingConfiguration``.
///
/// ```swift
/// .sheet(isPresented: $showVerification) {
///     VIDVerificationFlowView { result in
///         if case .verified(let outcome) = result {
///             print(outcome.document.mrz.surname)
///         }
///     }
/// }
/// ```
public struct VIDVerificationFlowView: View {

    private enum Step: Equatable {
        case intro
        case chipGuidance
        case readingChip
        case faceIntro
        case result
    }

    private let configuration: VIDConfiguration
    private let onCompletion: (VIDVerificationResult) -> Void

    @Environment(\.vidTheme) private var theme
    @State private var step: Step = .intro
    @State private var isScanning = false
    @State private var isCapturingFace = false
    @State private var scannedMRZ: VIDMRZData?
    @State private var passport: VIDPassportData?
    @State private var liveness: VIDLivenessOutcome?
    @State private var faceMatch: VIDFaceMatchResult?
    @State private var errorMessage: String?
    @State private var debugPhotoItem: PhotosPickerItem?
    @State private var debugReferenceOverride: CGImage?

    public init(
        configuration: VIDConfiguration = .default,
        onCompletion: @escaping (VIDVerificationResult) -> Void
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
    }

    /// The MRZ scanner config, with the document kind taken from the flow's
    /// `documentScan` step so the reticle matches what's being scanned.
    private var scannerConfiguration: VIDMRZConfiguration {
        var mrz = configuration.mrz
        for case let .documentScan(kind) in configuration.steps {
            mrz.documentKind = kind
            break
        }
        return mrz
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background)
            .fullScreenCover(isPresented: $isScanning) {
                VIDMRZScannerView(configuration: scannerConfiguration) { mrz in
                    scannedMRZ = mrz
                    isScanning = false
                    // Coach the user on chip position before raising the system
                    // NFC sheet — top KYC apps never ambush with the OS prompt.
                    step = .chipGuidance
                } onError: { error in
                    isScanning = false
                    onCompletion(.failed(error))
                } onClose: {
                    isScanning = false
                }
                .vidTheme(theme)
            }
            .fullScreenCover(isPresented: $isCapturingFace) {
                if let reference = referenceFace {
                    VIDFaceCaptureView(reference: reference, configuration: configuration.face) { liveness, match in
                        self.liveness = liveness
                        self.faceMatch = match
                        isCapturingFace = false
                        step = .result
                    } onCancel: {
                        // Skipping the selfie still yields a valid document+chip
                        // result — face fields just stay nil.
                        isCapturingFace = false
                        step = .result
                    }
                    .vidTheme(theme)
                }
            }
    }

    /// The reference face used for matching — normally the document portrait
    /// (chip DG2). In DEBUG, a developer-picked photo overrides it so the live
    /// scan matches against a chosen image instead of the chip photo.
    private var referenceFace: CGImage? {
        #if DEBUG
        if let debugReferenceOverride { return debugReferenceOverride }
        #endif
        guard let data = passport?.faceImageData, let image = UIImage(data: data) else { return nil }
        return image.cgImage
    }

    /// Whether to run the face step: it's configured, the chip gave us a portrait
    /// to match against, and a face model is bundled.
    private var shouldRunFaceMatch: Bool {
        configuration.steps.contains(.faceMatch) && referenceFace != nil
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro: intro
        case .chipGuidance: chipGuidance
        case .readingChip: readingChip
        case .faceIntro: faceIntro
        case .result: resultScreen
        }
    }

    // MARK: Intro

    @ViewBuilder
    private var intro: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            if let logoData = configuration.ui.branding.logoImageData,
               let uiImage = UIImage(data: logoData) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
            }

            Text("Verify your identity", bundle: .module)
                .font(theme.font(.largeTitle))
                .foregroundStyle(theme.textPrimary)

            Text("Scan your passport or ID, read its chip, and confirm it's really you. Everything happens on this device.", bundle: .module)
                .font(theme.font(.body))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            primaryButton(titleKey: "Start") { isScanning = true }
            secondaryButton(titleKey: "Cancel") { onCompletion(.cancelled) }
            poweredByBadge
        }
        .padding(theme.screenPadding)
    }

    // MARK: Chip guidance (pre-NFC coaching)

    /// Shown after the MRZ is read, before the system NFC sheet appears. Coaches
    /// the user on chip position so the read succeeds on the first try — the
    /// pattern every top-tier KYC flow uses instead of raising the OS prompt cold.
    @ViewBuilder
    private var chipGuidance: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.primary)

            Text("Now read the chip", bundle: .module)
                .font(theme.font(.largeTitle))
                .foregroundStyle(theme.textPrimary)

            Text("Your document has an NFC chip. Keep it flat on a surface.", bundle: .module)
                .font(theme.font(.body))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                guidanceRow("iphone.gen3", "Remove any case or cover from your iPhone.")
                guidanceRow("rectangle.portrait.and.arrow.forward", "Rest the top of your iPhone on the document.")
                guidanceRow("hand.raised.fill", "Hold still until the read completes.")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))

            Spacer()

            primaryButton(titleKey: "Scan chip") {
                if let mrz = scannedMRZ { startChipRead(mrz: mrz) }
            }
            secondaryButton(titleKey: "Cancel") { onCompletion(.cancelled) }
        }
        .padding(theme.screenPadding)
    }

    @ViewBuilder
    private func guidanceRow(_ systemImage: String, _ textKey: LocalizedStringKey) -> some View {
        Label {
            Text(textKey, bundle: .module)
                .font(theme.font(.body))
                .foregroundStyle(theme.textPrimary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.primary)
        }
    }

    // MARK: Reading chip

    @ViewBuilder
    private var readingChip: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(theme.primary)
            Text("Reading your passport…", bundle: .module)
                .font(theme.font(.headline))
                .foregroundStyle(theme.textPrimary)
            Text("Hold your iPhone against the passport until reading completes.", bundle: .module)
                .font(theme.font(.body))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(theme.screenPadding)
    }

    // MARK: Face intro

    /// Bridges the chip read and the selfie: shows the document portrait and what
    /// happens next, then launches the liveness capture on tap.
    @ViewBuilder
    private var faceIntro: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()
            if let reference = referenceFace {
                Image(decorative: reference, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: 96, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).stroke(theme.primary.opacity(0.3)))
            }
            Text("Now let's check it's you", bundle: .module)
                .font(theme.font(.largeTitle))
                .foregroundStyle(theme.textPrimary)
            Text("Follow a couple of quick prompts so we can match your face to the photo in your document. It only takes a moment.", bundle: .module)
                .font(theme.font(.body))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            primaryButton(titleKey: "Start face scan") { isCapturingFace = true }
            secondaryButton(titleKey: "Skip") { step = .result }

            #if DEBUG
            // Developer testing: replace the reference (document) photo with a
            // library image, so the live face scan matches against THAT instead of
            // the chip photo. Compiled out of release builds.
            if configuration.face.allowsDebugPhotoMatch {
                PhotosPicker(selection: $debugPhotoItem, matching: .images) {
                    Label(
                        debugReferenceOverride == nil ? "Use a photo as reference (testing)" : "Reference photo set ✓ — tap to change",
                        systemImage: "photo.on.rectangle"
                    )
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.textSecondary)
                }
                .onChange(of: debugPhotoItem) { _, item in loadDebugReference(item) }
            }
            #endif
        }
        .padding(theme.screenPadding)
    }

    #if DEBUG
    /// Loads a picked library photo and uses it as the match reference, so the
    /// normal live face scan compares against it instead of the chip photo.
    private func loadDebugReference(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                if let data, let cgImage = UIImage(data: data)?.vidUprightCGImage {
                    debugReferenceOverride = cgImage
                }
            }
        }
    }
    #endif

    // MARK: Result

    @ViewBuilder
    private var resultScreen: some View {
        VStack(spacing: theme.screenPadding) {
            if let passport {
                Spacer()
                if let faceData = passport.faceImageData, let image = UIImage(data: faceData) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 96, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                }
                Text(verbatim: "\(passport.mrz.givenNames) \(passport.mrz.surname)")
                    .font(theme.font(.title))
                    .foregroundStyle(theme.textPrimary)

                if configuration.ui.showDataReview {
                    VStack(alignment: .leading, spacing: 12) {
                        reviewRow("Document", passport.mrz.documentNumber)
                        reviewRow("Nationality", passport.mrz.nationality)
                        reviewRow("Sex", passport.mrz.sexDescription ?? "")
                        reviewRow("Date of birth", passport.mrz.formattedDateOfBirth ?? passport.mrz.birthDate)
                        reviewRow("Expiry", passport.mrz.formattedDateOfExpiry ?? passport.mrz.expiryDate,
                                  valueColor: passport.mrz.isExpired ? theme.error : nil)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
                }

                // The chip is access-controlled by the scanned MRZ, so a
                // successful read proves the scanned document matches the chip.
                if mrzMatchesChip {
                    badgeLabel("Scanned MRZ matches the chip", systemImage: "checkmark.circle.fill", color: theme.success)
                }
                authenticityBadge(passport.authenticity.passiveAuthentication)
                antiCloneBadge(passport.authenticity)
                if let faceMatch { faceMatchBadge(faceMatch) }

                Spacer()
                primaryButton(titleKey: "Done") {
                    onCompletion(.verified(VIDVerificationOutcome(
                        document: passport, liveness: liveness, faceMatch: faceMatch)))
                }
            } else {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(theme.error)
                Text("Could not read your passport", bundle: .module)
                    .font(theme.font(.title))
                    .foregroundStyle(theme.textPrimary)
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(theme.font(.body))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                primaryButton(titleKey: "Try again") { step = .intro }
                secondaryButton(titleKey: "Cancel") { onCompletion(.cancelled) }
            }
        }
        .padding(theme.screenPadding)
    }

    /// Whether the scanned MRZ's access-controlled fields match the chip's DG1.
    private var mrzMatchesChip: Bool {
        guard let scanned = scannedMRZ, let chip = passport?.mrz else { return false }
        return scanned.documentNumber == chip.documentNumber
            && scanned.birthDate == chip.birthDate
            && scanned.expiryDate == chip.expiryDate
    }

    // MARK: Chip read

    private func startChipRead(mrz: VIDMRZData) {
        step = .readingChip
        let key = VIDMRZKey(
            documentNumber: mrz.documentNumber,
            birthDate: mrz.birthDate,
            expiryDate: mrz.expiryDate
        )
        Task {
            do {
                let data = try await VIDPassportReader(configuration: configuration.nfc).read(mrzKey: key)
                await MainActor.run {
                    passport = data
                    // Chain into the face step when configured and the chip gave
                    // us a portrait to match against; otherwise show the result.
                    step = shouldRunFaceMatch ? .faceIntro : .result
                }
            } catch let error as VIDError {
                await MainActor.run {
                    // Cancelling the NFC sheet returns to the chip-guidance screen so
                    // the user can retry the read without re-scanning the MRZ; a real
                    // failure shows the result.
                    if case .cancelledByUser = error { step = .chipGuidance }
                    else { errorMessage = error.errorDescription; step = .result }
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; step = .result }
            }
        }
    }

    // MARK: Components

    @ViewBuilder
    private func authenticityBadge(_ result: VIDPassiveAuthenticationResult) -> some View {
        let showDetails = configuration.ui.showsSecurityDetails
        switch (result.dataIntegrity, result.chainOfTrust) {
        case (.passed, .passed):
            badgeLabel("Chip verified", systemImage: "checkmark.seal.fill", color: theme.success)
        case (.passed, _):
            // Data is intact and signed, but the issuer chain wasn't fully
            // confirmed (e.g. that country's CSCA isn't in the trust store).
            // That's a developer/integration concern, not something to alarm an
            // end user with — only surface it in detail mode, and render nothing
            // (not an empty container that would leave a gap) otherwise. The
            // specific reason (e.g. "add the CSCA for [CN=…]") stays on the result.
            if showDetails {
                VStack(spacing: 4) {
                    badgeLabel("Chip data intact", systemImage: "checkmark.shield.fill", color: theme.primary)
                    detailText(result.chainOfTrust.reason)
                }
            }
        default:
            // Data integrity itself failed — a genuine problem worth surfacing.
            VStack(spacing: 4) {
                badgeLabel("Chip could not be verified", systemImage: "exclamationmark.shield.fill", color: theme.warning)
                if showDetails { detailText(result.dataIntegrity.reason) }
            }
        }
    }

    /// Small muted caption for developer-facing security detail.
    @ViewBuilder
    private func detailText(_ reason: String?) -> some View {
        if let reason {
            Text(verbatim: reason)
                .font(theme.font(.caption))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Shows the anti-clone result when the chip supports Chip or Active
    /// Authentication (both prove the physical chip is genuine, not a copy).
    @ViewBuilder
    private func antiCloneBadge(_ result: VIDChipAuthenticityResult) -> some View {
        if result.chipAuthentication.isPassed || result.activeAuthentication.isPassed {
            badgeLabel("Genuine chip confirmed", systemImage: "cpu.fill", color: theme.success)
        } else if case .failed = result.chipAuthentication {
            badgeLabel("Chip authenticity check failed", systemImage: "cpu", color: theme.error)
        } else if case .failed = result.activeAuthentication {
            badgeLabel("Chip authenticity check failed", systemImage: "cpu", color: theme.error)
        }
    }

    /// Shows the face-match verdict with the two faces side by side.
    @ViewBuilder
    private func faceMatchBadge(_ result: VIDFaceMatchResult) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                thumbnail(result.referenceImageData)
                Image(systemName: result.isMatch ? "equal.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.isMatch ? theme.success : theme.error)
                thumbnail(result.liveImageData)
            }
            badgeLabel(
                result.isMatch ? "Face matches the document" : "Face did not match",
                systemImage: result.isMatch ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark",
                color: result.isMatch ? theme.success : theme.error
            )
            if configuration.ui.showsSecurityDetails {
                detailText("similarity \(String(format: "%.2f", result.similarity)) / threshold \(String(format: "%.2f", result.thresholdUsed))")
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: 56, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func badgeLabel(_ titleKey: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        Label {
            Text(titleKey, bundle: .module)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(theme.font(.caption))
        .foregroundStyle(color)
    }

    /// A Votari-style info row: muted label on the left, emphasized value on the
    /// right. Rows with an empty value are hidden.
    @ViewBuilder
    private func reviewRow(_ label: LocalizedStringKey, _ value: String, valueColor: Color? = nil) -> some View {
        if !value.isEmpty {
            HStack(spacing: 0) {
                Text(label, bundle: .module).foregroundStyle(theme.textSecondary)
                Spacer(minLength: 12)
                Text(verbatim: value)
                    .foregroundStyle(valueColor ?? theme.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .font(theme.font(.body))
        }
    }

    @ViewBuilder
    private func primaryButton(titleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titleKey, bundle: .module)
                .font(theme.font(.button))
                .foregroundStyle(theme.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(theme.primary, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
        }
    }

    @ViewBuilder
    private func secondaryButton(titleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titleKey, bundle: .module)
                .font(theme.font(.button))
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder
    private var poweredByBadge: some View {
        if configuration.ui.branding.showsPoweredByBadge {
            Label {
                Text("Secured on-device by VerifID", bundle: .module)
            } icon: {
                Image(systemName: "lock.shield.fill")
            }
            .font(theme.font(.caption))
            .foregroundStyle(theme.textSecondary.opacity(0.7))
            .padding(.top, 4)
        }
    }
}

#if DEBUG
private extension UIImage {
    /// The image redrawn with `.up` orientation so its `CGImage` has upright
    /// pixels for Vision (library photos carry EXIF rotation).
    var vidUprightCGImage: CGImage? {
        guard imageOrientation != .up else { return cgImage }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized?.cgImage
    }
}
#endif
