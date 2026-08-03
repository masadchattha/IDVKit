//
//  IDVVerificationFlowView.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import IDVKitCore
import IDVKitFace
import IDVKitMRZ
import IDVKitNFC
import PhotosUI
import SwiftUI

/// The drop-in verification flow: **Intro → scan MRZ → read NFC chip → result**.
///
/// The flow reads the passport's machine-readable zone to derive the chip-access
/// key, opens the NFC chip (PACE or BAC), reads the data groups, runs passive
/// authentication, and shows a result. Face match/liveness is a later step.
/// Everything happens on-device. Themeable via `.idvTheme(_:)`, brandable via
/// ``IDVBrandingConfiguration``.
///
/// ```swift
/// .sheet(isPresented: $showVerification) {
///     IDVVerificationFlowView { result in
///         if case .verified(let outcome) = result {
///             print(outcome.document.mrz.surname)
///         }
///     }
/// }
/// ```
public struct IDVVerificationFlowView: View {
    private enum Step: Equatable {
        case intro
        case documentSelection
        case documentScanGuidance
        case documentIssue
        case chipGuidance
        case readingChip
        case faceIntro
        case result
    }

    /// Resolves a hero illustration: a developer override, else the illustration
    /// IDVKit ships in its own bundle, else `nil` (the screen shows a symbol).
    private func heroData(_ override: Data?, default name: String) -> Data? {
        if let override {
            return override
        }
        return Bundle.module.url(forResource: name, withExtension: "png")
            .flatMap { try? Data(contentsOf: $0) }
    }

    /// A document-type problem detected from the scanned MRZ (never trusting the
    /// user's pick as ground truth — the MRZ layout and document code decide).
    private enum DocumentIssue: Equatable {
        /// The detected type isn't in `allowedDocuments`.
        case notAccepted(detected: IDVVerificationStep.DocumentKind)
        /// The detected type is accepted but differs from what the user picked.
        case pickMismatch(detected: IDVVerificationStep.DocumentKind,
                          picked: IDVVerificationStep.DocumentKind)
    }

    private let configuration: IDVConfiguration
    private let onCompletion: (IDVVerificationResult) -> Void

    @Environment(\.idvTheme) private var theme
    @State private var step: Step = .intro
    @State private var isScanning = false
    @State private var isCapturingFace = false
    @State private var scannedMRZ: IDVMRZData?
    @State private var passport: IDVPassportData?
    @State private var liveness: IDVLivenessOutcome?
    @State private var faceMatch: IDVFaceMatchResult?
    @State private var errorMessage: String?
    @State private var debugPhotoItem: PhotosPickerItem?
    @State private var debugReferenceOverride: CGImage?
    /// The document type the user picked on the selection screen, when the flow
    /// offers a choice. Drives the scanner reticle; recognition auto-detects.
    @State private var selectedDocumentKind: IDVVerificationStep.DocumentKind?
    /// A detected document-type problem, shown on the `.documentIssue` screen.
    @State private var documentIssue: DocumentIssue?
    /// Whether the NFC "tips for reading the chip" help alert is shown.
    @State private var showNFCHelp = false
    #if DEBUG
        /// DEBUG-only: overrides the liveness path from the face-intro screen so
        /// both paths can be exercised after a real scan. Not shipping API.
        @State private var debugLivenessMode: IDVLivenessMode = .headRotation
    #endif

    public init(
        configuration: IDVConfiguration = .default,
        onCompletion: @escaping (IDVVerificationResult) -> Void
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
    }

    #if DEBUG
        /// DEBUG-only: opens the flow at a specific screen with mock data so the
        /// static screens can be reviewed in the Simulator (which can't run the
        /// camera or NFC). Compiled out of release builds; not shipping API.
        public init(
            configuration: IDVConfiguration = .default,
            debugStartAt screen: String,
            debugFaceImageData: Data? = nil,
            onCompletion: @escaping (IDVVerificationResult) -> Void
        ) {
            self.configuration = configuration
            self.onCompletion = onCompletion
            let mockMRZ = IDVMRZData(
                format: .td3, documentType: "P", issuingCountry: "USA",
                documentNumber: "X1234567", nationality: "USA", surname: "CARTER",
                givenNames: "EMMA", birthDate: "980314", expiryDate: "320314", sex: "F"
            )
            _scannedMRZ = State(initialValue: mockMRZ)
            let step: Step = switch screen {
            case "documentSelection": .documentSelection
            case "documentScanGuidance": .documentScanGuidance
            case "chipGuidance": .chipGuidance
            case "faceIntro": .faceIntro
            case "result", "resultSuccess": .result
            default: .intro
            }
            _step = State(initialValue: step)
            // `resultSuccess` populates a fully-verified specimen read (fake USA
            // data, all authenticity checks green) so the success result screen can
            // be captured in the Simulator without a device/NFC.
            if screen == "resultSuccess" {
                _passport = State(initialValue: IDVPassportData(
                    mrz: mockMRZ,
                    faceImageData: debugFaceImageData,
                    dataGroupsRead: [.com, .dg1, .dg2, .dg15, .sod],
                    authenticity: IDVChipAuthenticityResult(
                        passiveAuthentication: IDVPassiveAuthenticationResult(
                            dataIntegrity: .passed, chainOfTrust: .passed
                        ),
                        chipAuthentication: .passed,
                        activeAuthentication: .passed
                    )
                ))
            }
        }
    #endif

    /// The MRZ scanner config, with the document kind taken from the flow's
    /// `documentScan` step so the reticle matches what's being scanned.
    private var scannerConfiguration: IDVMRZConfiguration {
        var mrz = configuration.mrz
        // A user pick (from the selection screen) wins; otherwise fall back to
        // the document kind declared on the flow's `documentScan` step.
        if let selectedDocumentKind {
            mrz.documentKind = selectedDocumentKind
        } else {
            for case let .documentScan(kind) in configuration.steps {
                mrz.documentKind = kind
                break
            }
        }
        return mrz
    }

    /// Begins scanning, routing through the document-type picker first when the
    /// configuration offers a choice between two or more concrete kinds.
    private func beginDocumentCapture() {
        if configuration.mrz.offersDocumentChoice {
            step = .documentSelection
        } else {
            step = .documentScanGuidance
        }
    }

    /// Decides where to go after a successful MRZ scan. The MRZ — not the user's
    /// pick — is the source of truth for the document type (ICAO 9303). We reject
    /// a type the integrator doesn't accept, surface a pick/scan mismatch, and
    /// otherwise proceed to the chip.
    private func routeAfterScan(_ mrz: IDVMRZData) {
        let detected = mrz.detectedDocumentKind
        let accepted = configuration.mrz.allowedDocuments.contains { mrz.matches($0) }

        if !accepted {
            documentIssue = .notAccepted(detected: detected)
            step = .documentIssue
        } else if let picked = selectedDocumentKind, !mrz.matches(picked) {
            documentIssue = .pickMismatch(detected: detected, picked: picked)
            step = .documentIssue
        } else {
            // Coach the user on chip position before raising the system NFC
            // sheet — top KYC apps never ambush with the OS prompt.
            step = .chipGuidance
        }
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background)
            // Verification is a deliberate, multi-step flow — an accidental
            // swipe-down mid-scan would lose progress. The only way out is the
            // explicit Cancel button on every screen.
            .interactiveDismissDisabled()
            .fullScreenCover(isPresented: $isScanning) {
                IDVMRZScannerView(configuration: scannerConfiguration) { mrz in
                    scannedMRZ = mrz
                    isScanning = false
                    routeAfterScan(mrz)
                } onError: { error in
                    isScanning = false
                    onCompletion(.failed(error))
                } onClose: {
                    isScanning = false
                }
                .idvTheme(theme)
            }
            .fullScreenCover(isPresented: $isCapturingFace) {
                if let reference = referenceFace {
                    IDVFaceCaptureView(reference: reference, configuration: faceConfiguration) { liveness, match in
                        self.liveness = liveness
                        faceMatch = match
                        isCapturingFace = false
                        step = .result
                    } onCancel: {
                        // Skipping the selfie still yields a valid document+chip
                        // result — face fields just stay nil.
                        isCapturingFace = false
                        step = .result
                    }
                    .idvTheme(theme)
                }
            }
    }

    /// The reference face used for matching — normally the document portrait
    /// (chip DG2). In DEBUG, a developer-picked photo overrides it so the live
    /// scan matches against a chosen image instead of the chip photo.
    private var referenceFace: CGImage? {
        #if DEBUG
            if let debugReferenceOverride {
                return debugReferenceOverride
            }
        #endif
        guard let data = passport?.faceImageData, let image = UIImage(data: data) else { return nil }
        return image.cgImage
    }

    /// Whether to run the face step: it's configured, the chip gave us a portrait
    /// to match against, and a face model is bundled.
    private var shouldRunFaceMatch: Bool {
        configuration.steps.contains(.faceMatch) && referenceFace != nil
    }

    /// The face configuration handed to the capture view. In DEBUG the face-intro
    /// picker can override the liveness path so both can be tested from the real
    /// flow; release builds always use the integrator's configuration verbatim.
    private var faceConfiguration: IDVFaceConfiguration {
        #if DEBUG
            var config = configuration.face
            config.livenessMode = debugLivenessMode
            return config
        #else
            configuration.face
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro: intro
        case .documentSelection: documentSelection
        case .documentScanGuidance: documentScanGuidance
        case .documentIssue: documentIssueScreen
        case .chipGuidance: chipGuidance
        case .readingChip: readingChip
        case .faceIntro: faceIntro
        case .result: resultScreen
        }
    }

    // MARK: Shared layout

    /// A title + supporting subtitle, centered. Assets sit *below* this.
    private func screenHeader(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: IDVLayout.Spacing.title) {
            Text(title, bundle: .module)
                .font(theme.font(.largeTitle))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle, bundle: .module)
                .font(theme.font(.body))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            screenHeader(IDVStrings.Intro.title, IDVStrings.Intro.subtitle)

            if let logoData = configuration.ui.branding.logoImageData,
               let uiImage = UIImage(data: logoData) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFit()
                    .frame(width: IDVLayout.Size.logo, height: IDVLayout.Size.logo)
                    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
            } else {
                heroSymbol(IDVIcon.intro,
                           illustration: heroData(configuration.ui.illustrations.intro, default: "idv-illus-intro"))
            }

            Spacer()

            primaryButton(titleKey: IDVStrings.Button.start) { beginDocumentCapture() }
            secondaryButton(titleKey: IDVStrings.Button.cancel) { onCompletion(.cancelled) }
            poweredByBadge
        }
        .padding(theme.screenPadding)
    }

    // MARK: Document selection

    /// Shown before scanning when the configuration offers a choice of document
    /// types. A calm card list — the pattern Persona/Onfido/Jumio converge on —
    /// with one large tappable row per kind. Picking one shapes the scanner
    /// reticle and starts the camera.
    private var documentSelection: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            VStack(spacing: IDVLayout.Spacing.small) {
                Text(IDVStrings.DocumentSelection.title, bundle: .module)
                    .font(theme.font(.largeTitle))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(IDVStrings.DocumentSelection.subtitle, bundle: .module)
                    .font(theme.font(.body))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: IDVLayout.Spacing.medium) {
                ForEach(configuration.mrz.selectableDocuments, id: \.self) { kind in
                    documentOptionRow(kind)
                }
            }
            .padding(.top, IDVLayout.Spacing.small)

            Spacer()

            secondaryButton(titleKey: IDVStrings.Button.cancel) { onCompletion(.cancelled) }
            poweredByBadge
        }
        .padding(theme.screenPadding)
    }

    private func documentOptionRow(_ kind: IDVVerificationStep.DocumentKind) -> some View {
        Button {
            selectedDocumentKind = kind
            step = .documentScanGuidance
        } label: {
            HStack(spacing: IDVLayout.Spacing.large) {
                Image(systemName: kind.idvIconName)
                    .font(.system(size: IDVLayout.IconSize.row))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.primary)
                    .frame(width: IDVLayout.Size.rowIconSlot)

                VStack(alignment: .leading, spacing: IDVLayout.Spacing.micro) {
                    Text(kind.idvTitleKey, bundle: .module)
                        .font(theme.font(.headline))
                        .foregroundStyle(theme.textPrimary)
                    Text(kind.idvSubtitleKey, bundle: .module)
                        .font(theme.font(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
                .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: IDVIcon.chevron)
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(theme.screenPadding * IDVLayout.Scale.rowPaddingFactor)
            .frame(maxWidth: .infinity)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .strokeBorder(theme.textSecondary.opacity(IDVLayout.Opacity.tint))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Document scan guidance (before the camera)

    /// Coaches the user on positioning the document before the camera opens —
    /// the same "tell them what to do first" pattern the chip and face steps use.
    private var documentScanGuidance: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            screenHeader(IDVStrings.ScanGuidance.title, IDVStrings.ScanGuidance.subtitle)

            heroSymbol(IDVIcon.documentScan,
                       illustration: heroData(configuration.ui.illustrations.documentScan, default: "idv-illus-scan"))

            chipRequirementNote

            Spacer()

            primaryButton(titleKey: IDVStrings.Button.scanDocument) { isScanning = true }
            secondaryButton(titleKey: IDVStrings.Button.cancel) { onCompletion(.cancelled) }
        }
        .padding(theme.screenPadding)
    }

    /// Educates the user that the document needs a readable NFC chip, showing the
    /// "chip inside" symbol to look for. Copy adapts to the chosen document kind —
    /// passports print the symbol on the cover; cards vary front/back.
    private var chipRequirementNote: some View {
        HStack(spacing: IDVLayout.Spacing.row) {
            IDVChipSymbol(tint: theme.primary)
            Text(chipNoteText, bundle: .module)
                .font(theme.font(.caption))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }

    private var chipNoteText: LocalizedStringKey {
        switch selectedDocumentKind {
        case .passport:
            IDVStrings.ScanGuidance.chipNotePassport
        case .idCard, .residencePermit:
            IDVStrings.ScanGuidance.chipNoteCard
        default:
            IDVStrings.ScanGuidance.chipNoteGeneric
        }
    }

    // MARK: Document issue (detected type not accepted, or ≠ the user's pick)

    /// Shown when the scanned MRZ's detected document type isn't accepted, or
    /// differs from what the user picked. The MRZ is the source of truth, so we
    /// surface the mismatch rather than silently proceeding with the wrong label.
    private var documentIssueScreen: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            Image(systemName: IDVIcon.warning)
                .font(.system(size: IDVLayout.IconSize.warning))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.warning)

            switch documentIssue {
            case let .notAccepted(detected):
                Text(IDVStrings.DocumentIssue.notAcceptedTitle, bundle: .module)
                    .font(theme.font(.largeTitle))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(verbatim: IDVStrings.DocumentIssue.notAcceptedBody(detected.idvNoun))
                    .font(theme.font(.body))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)

                Spacer()

                if configuration.mrz.offersDocumentChoice {
                    primaryButton(titleKey: IDVStrings.Button.chooseType) {
                        documentIssue = nil
                        step = .documentSelection
                    }
                    secondaryButton(titleKey: IDVStrings.Button.scanAgain) { retryScan() }
                } else {
                    primaryButton(titleKey: IDVStrings.Button.scanAgain) { retryScan() }
                }
                secondaryButton(titleKey: IDVStrings.Button.cancel) { onCompletion(.cancelled) }

            case let .pickMismatch(detected, picked):
                Text(verbatim: IDVStrings.DocumentIssue.PickMismatch.title(detected.idvNoun))
                    .font(theme.font(.largeTitle))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(verbatim: IDVStrings.DocumentIssue.PickMismatch.body(picked: picked.idvNoun, detected: detected.idvNoun))
                    .font(theme.font(.body))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)

                Spacer()

                primaryButton(titleKey: IDVStrings.Button.proceed) {
                    // Trust the detection over the pick.
                    selectedDocumentKind = detected
                    documentIssue = nil
                    step = .chipGuidance
                }
                secondaryButton(titleKey: IDVStrings.Button.chooseDifferent) {
                    documentIssue = nil
                    step = .documentSelection
                }
                secondaryButton(titleKey: IDVStrings.Button.scanAgain) { retryScan() }

            case .none:
                Spacer()
            }

            poweredByBadge
        }
        .padding(theme.screenPadding)
    }

    private func retryScan() {
        documentIssue = nil
        scannedMRZ = nil
        isScanning = true
    }

    // MARK: Chip guidance (pre-NFC coaching)

    /// Shown after the MRZ is read, before the system NFC sheet appears. Coaches
    /// the user on chip position so the read succeeds on the first try — the
    /// pattern every top-tier KYC flow uses instead of raising the OS prompt cold.
    private var chipGuidance: some View {
        VStack(spacing: theme.screenPadding) {
            HStack {
                Spacer()
                helpButton
            }
            Spacer()

            screenHeader(IDVStrings.ChipGuidance.title, IDVStrings.ChipGuidance.subtitle)

            // The chip screen is the one place a motion tutorial measurably helps
            // (users have no mental model of the antenna). Default to a native
            // animated tap; a developer-supplied illustration overrides it.
            if let chipIllustration = configuration.ui.illustrations.chipGuidance {
                heroSymbol(IDVIcon.chipGuidance, illustration: chipIllustration)
            } else {
                IDVNFCTapAnimation(tint: theme.primary)
            }

            VStack(alignment: .leading, spacing: IDVLayout.Spacing.medium) {
                guidanceRow(IDVIcon.restPhone, IDVStrings.ChipGuidance.rowRest)
                guidanceRow(IDVIcon.holdStill, IDVStrings.ChipGuidance.rowHoldStill)
                guidanceRow(IDVIcon.phoneCase, IDVStrings.ChipGuidance.rowCase)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))

            Spacer()

            primaryButton(titleKey: IDVStrings.Button.scanChip) {
                if let mrz = scannedMRZ {
                    startChipRead(mrz: mrz)
                }
            }
            secondaryButton(titleKey: IDVStrings.Button.cancel) { onCompletion(.cancelled) }
        }
        .padding(theme.screenPadding)
        .idvNFCHelpAlert(isPresented: $showNFCHelp)
    }

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

    private var readingChip: some View {
        VStack(spacing: theme.screenPadding) {
            HStack {
                Spacer()
                helpButton
            }
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(theme.primary)
            Text(IDVStrings.ReadingChip.title, bundle: .module)
                .font(theme.font(.headline))
                .foregroundStyle(theme.textPrimary)
            Text(IDVStrings.ReadingChip.subtitle, bundle: .module)
                .font(theme.font(.body))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(theme.screenPadding)
        .idvNFCHelpAlert(isPresented: $showNFCHelp)
    }

    /// A top-bar help button that opens the NFC "tips for reading the chip" alert.
    private var helpButton: some View {
        Button { showNFCHelp = true } label: {
            Label(IDVStrings.Help.button, systemImage: IDVIcon.help)
                .font(theme.font(.body))
                .foregroundStyle(theme.primary)
        }
    }

    // MARK: Face intro

    /// Bridges the chip read and the selfie: shows the document portrait and what
    /// happens next, then launches the liveness capture on tap.
    private var faceIntro: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            screenHeader(IDVStrings.FaceIntro.title, IDVStrings.FaceIntro.subtitle)

            if let reference = referenceFace {
                Image(decorative: reference, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: IDVLayout.Size.facePortraitWidth, height: IDVLayout.Size.facePortraitHeight)
                    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).stroke(theme.primary.opacity(IDVLayout.Opacity.subtle)))
            } else {
                heroSymbol(IDVIcon.faceIntro,
                           illustration: heroData(configuration.ui.illustrations.faceIntro, default: "idv-illus-face"))
            }

            Spacer()
            primaryButton(titleKey: IDVStrings.Button.startFaceScan) { isCapturingFace = true }
            secondaryButton(titleKey: IDVStrings.Button.skip) { step = .result }

            #if DEBUG
                // Developer testing: pick which liveness path the capture runs, so
                // both can be exercised after a real scan on device. Compiled out of
                // release builds; integrators set this via `IDVFaceConfiguration`.
                Picker(selection: $debugLivenessMode) {
                    Text(verbatim: "Head rotation (ring)").tag(IDVLivenessMode.headRotation)
                    Text(verbatim: "Random prompts").tag(IDVLivenessMode.activeChallenges)
                    Text(verbatim: "Both").tag(IDVLivenessMode.both)
                    Text(verbatim: "Passive").tag(IDVLivenessMode.passive)
                } label: {
                    Text(verbatim: "Liveness path (debug)")
                }
                .font(theme.font(.caption))
                .tint(theme.primary)

                // Developer testing: replace the reference (document) photo with a
                // library image, so the live face scan matches against THAT instead of
                // the chip photo. Compiled out of release builds.
                if configuration.face.allowsDebugPhotoMatch {
                    // Hoist the @MainActor-isolated values here (this builder body is
                    // MainActor); the PhotosPicker label closure is not MainActor-
                    // isolated under strict concurrency, so it may only capture these
                    // Sendable copies — not `theme`/`debugReferenceOverride` directly.
                    let pickerLabel = debugReferenceOverride == nil
                        ? IDVStrings.Debug.usePhoto
                        : IDVStrings.Debug.photoSet
                    let captionFont = theme.font(.caption)
                    let captionColor = theme.textSecondary
                    PhotosPicker(selection: $debugPhotoItem, matching: .images) {
                        Label(pickerLabel, systemImage: IDVIcon.debugPhoto)
                            .font(captionFont)
                            .foregroundStyle(captionColor)
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
                    if let data, let cgImage = UIImage(data: data)?.idvUprightCGImage {
                        debugReferenceOverride = cgImage
                    }
                }
            }
        }
    #endif

    // MARK: Result

    private var resultScreen: some View {
        VStack(spacing: theme.screenPadding) {
            if let passport {
                Spacer()
                if let faceData = passport.faceImageData, let image = UIImage(data: faceData) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: IDVLayout.Size.resultPhotoWidth, height: IDVLayout.Size.resultPhotoHeight)
                        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                }
                Text(verbatim: "\(passport.mrz.givenNames) \(passport.mrz.surname)")
                    .font(theme.font(.title))
                    .foregroundStyle(theme.textPrimary)

                if configuration.ui.showDataReview {
                    VStack(alignment: .leading, spacing: IDVLayout.Spacing.medium) {
                        reviewRow(IDVStrings.Result.Row.document, passport.mrz.documentNumber)
                        reviewRow(IDVStrings.Result.Row.nationality, passport.mrz.nationality)
                        reviewRow(IDVStrings.Result.Row.sex, passport.mrz.sexDescription ?? "")
                        reviewRow(IDVStrings.Result.Row.dateOfBirth, passport.mrz.formattedDateOfBirth ?? passport.mrz.birthDate)
                        reviewRow(IDVStrings.Result.Row.expiry, passport.mrz.formattedDateOfExpiry ?? passport.mrz.expiryDate,
                                  valueColor: passport.mrz.isExpired ? theme.error : nil)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
                }

                // Success badges, grouped and left-aligned.
                VStack(alignment: .leading, spacing: IDVLayout.Spacing.medium) {
                    // The chip is access-controlled by the scanned MRZ, so a
                    // successful read proves the scanned document matches the chip.
                    if mrzMatchesChip {
                        badgeLabel(IDVStrings.Badge.mrzMatchesChip, systemImage: IDVIcon.mrzMatchesChip, color: theme.success)
                    }
                    authenticityBadge(passport.authenticity.passiveAuthentication)
                    antiCloneBadge(passport.authenticity)
                    if let faceMatch {
                        faceMatchBadge(faceMatch)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                primaryButton(titleKey: IDVStrings.Button.done) {
                    onCompletion(.verified(IDVVerificationOutcome(
                        document: passport, liveness: liveness, faceMatch: faceMatch
                    )))
                }
            } else {
                Spacer()
                ZStack {
                    Circle()
                        .fill(theme.error.opacity(IDVLayout.Opacity.tint))
                        .frame(width: IDVLayout.Size.heroCircle, height: IDVLayout.Size.heroCircle)
                    Image(systemName: IDVIcon.warning)
                        .font(.system(size: IDVLayout.IconSize.hero))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.error)
                }
                VStack(spacing: IDVLayout.Spacing.title) {
                    Text(IDVStrings.Result.couldNotRead, bundle: .module)
                        .font(theme.font(.largeTitle))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .font(theme.font(.body))
                            .foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                Button { showNFCHelp = true } label: {
                    Label(IDVStrings.Help.button, systemImage: IDVIcon.help)
                        .font(theme.font(.body))
                        .foregroundStyle(theme.primary)
                }
                .padding(.top, IDVLayout.Spacing.small)
                Spacer()
                // Retry just the chip read using the already-scanned MRZ — no need to
                // re-scan the document. Only fall back to the start if we somehow
                // have no MRZ to reuse.
                primaryButton(titleKey: IDVStrings.Button.tryAgain) {
                    if let scannedMRZ {
                        errorMessage = nil
                        startChipRead(mrz: scannedMRZ)
                    } else {
                        step = .intro
                    }
                }
                secondaryButton(titleKey: IDVStrings.Button.cancel) { onCompletion(.cancelled) }
            }
        }
        .padding(theme.screenPadding)
        .idvNFCHelpAlert(isPresented: $showNFCHelp)
    }

    /// Whether the scanned MRZ's access-controlled fields match the chip's DG1.
    private var mrzMatchesChip: Bool {
        guard let scanned = scannedMRZ, let chip = passport?.mrz else { return false }
        return scanned.documentNumber == chip.documentNumber
            && scanned.birthDate == chip.birthDate
            && scanned.expiryDate == chip.expiryDate
    }

    // MARK: Chip read

    private func startChipRead(mrz: IDVMRZData) {
        // Don't start (or retry) a read on a device that can't do NFC — retrying
        // there would just spin. (Simulator / unsupported hardware.)
        guard IDVPassportReader.isReadingAvailable else {
            Logger.nfc.idvError("Chip read requested but NFC isn't available on this device")
            errorMessage = IDVError.nfcNotSupported.errorDescription
            step = .result
            return
        }
        step = .readingChip
        let key = IDVMRZKey(
            documentNumber: mrz.documentNumber,
            birthDate: mrz.birthDate,
            expiryDate: mrz.expiryDate
        )
        Logger.nfc.idvDebug("Chip read starting for document \(mrz.documentNumber)")
        Task {
            // Give the NFC hardware a beat to release from any prior session, so a
            // quick retry doesn't hit a still-busy reader.
            try? await Task.sleep(for: .milliseconds(500))
            do {
                let data = try await IDVPassportReader(configuration: configuration.nfc).read(mrzKey: key)
                await MainActor.run {
                    Logger.nfc.idvDebug("Chip read succeeded")
                    passport = data
                    // Chain into the face step when configured and the chip gave
                    // us a portrait to match against; otherwise show the result.
                    step = shouldRunFaceMatch ? .faceIntro : .result
                }
            } catch let error as IDVError {
                await MainActor.run {
                    // Cancelling the NFC sheet returns to the chip-guidance screen so
                    // the user can retry the read without re-scanning the MRZ; a real
                    // failure shows the result.
                    if case .cancelledByUser = error {
                        Logger.nfc.idvDebug("Chip read cancelled by user → chip guidance")
                        step = .chipGuidance
                    } else {
                        Logger.nfc.idvError("Chip read failed: \(error.errorDescription ?? "?") → error screen")
                        errorMessage = error.errorDescription
                        step = .result
                    }
                }
            } catch {
                await MainActor.run {
                    Logger.nfc.idvError("Chip read failed (non-IDVError): \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                    step = .result
                }
            }
        }
    }

    // MARK: Components

    @ViewBuilder
    private func authenticityBadge(_ result: IDVPassiveAuthenticationResult) -> some View {
        let showDetails = configuration.ui.showsSecurityDetails
        switch (result.dataIntegrity, result.chainOfTrust) {
        case (.passed, .passed):
            badgeLabel(IDVStrings.Badge.chipVerified, systemImage: IDVIcon.chipVerified, color: theme.success)
        case (.passed, _):
            // Data is intact and signed, but the issuer chain wasn't fully
            // confirmed (e.g. that country's CSCA isn't in the trust store).
            // That's a developer/integration concern, not something to alarm an
            // end user with — only surface it in detail mode, and render nothing
            // (not an empty container that would leave a gap) otherwise. The
            // specific reason (e.g. "add the CSCA for [CN=…]") stays on the result.
            if showDetails {
                VStack(spacing: IDVLayout.Spacing.tiny) {
                    badgeLabel(IDVStrings.Badge.chipDataIntact, systemImage: IDVIcon.chipDataIntact, color: theme.primary)
                    detailText(result.chainOfTrust.reason)
                }
            }
        default:
            // Data integrity itself failed — a genuine problem worth surfacing.
            VStack(spacing: IDVLayout.Spacing.tiny) {
                badgeLabel(IDVStrings.Badge.chipUnverifiable, systemImage: IDVIcon.chipUnverifiable, color: theme.warning)
                if showDetails {
                    detailText(result.dataIntegrity.reason)
                }
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
    private func antiCloneBadge(_ result: IDVChipAuthenticityResult) -> some View {
        if result.chipAuthentication.isPassed || result.activeAuthentication.isPassed {
            badgeLabel(IDVStrings.Badge.genuineChip, systemImage: IDVIcon.genuineChip, color: theme.success)
        } else if case .failed = result.chipAuthentication {
            badgeLabel(IDVStrings.Badge.chipAuthFailed, systemImage: IDVIcon.chipAuthFailed, color: theme.error)
        } else if case .failed = result.activeAuthentication {
            badgeLabel(IDVStrings.Badge.chipAuthFailed, systemImage: IDVIcon.chipAuthFailed, color: theme.error)
        }
    }

    /// Shows the face-match verdict with the two faces side by side.
    private func faceMatchBadge(_ result: IDVFaceMatchResult) -> some View {
        VStack(spacing: IDVLayout.Spacing.small) {
            HStack(spacing: IDVLayout.Spacing.title) {
                thumbnail(result.referenceImageData)
                Image(systemName: result.isMatch ? IDVIcon.faceMatch : IDVIcon.faceMismatch)
                    .foregroundStyle(result.isMatch ? theme.success : theme.error)
                thumbnail(result.liveImageData)
            }
            badgeLabel(
                result.isMatch ? IDVStrings.Badge.faceMatches : IDVStrings.Badge.faceMismatch,
                systemImage: result.isMatch ? IDVIcon.faceMatchBadge : IDVIcon.faceMismatchBadge,
                color: result.isMatch ? theme.success : theme.error
            )
            if configuration.ui.showsSecurityDetails {
                detailText(IDVStrings.Badge.similarityDetail(result.similarity, threshold: result.thresholdUsed))
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: IDVLayout.Size.matchThumbWidth, height: IDVLayout.Size.matchThumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: IDVLayout.Radius.matchThumb))
        }
    }

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
            HStack(spacing: .zero) {
                Text(label, bundle: .module).foregroundStyle(theme.textSecondary)
                Spacer(minLength: IDVLayout.Spacing.medium)
                Text(verbatim: value)
                    .foregroundStyle(valueColor ?? theme.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .font(theme.font(.body))
        }
    }

    /// A screen's hero visual: a developer-supplied illustration if present,
    /// otherwise the given SF Symbol inside a soft tinted circle.
    @ViewBuilder
    private func heroSymbol(_ systemName: String, illustration: Data? = nil) -> some View {
        if let illustration, let uiImage = UIImage(data: illustration) {
            // Sit the illustration on a fixed soft panel so artwork with dark or
            // white fills reads cleanly on both light and dark app backgrounds.
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: IDVLayout.Size.illustrationMaxWidth, maxHeight: IDVLayout.Size.illustrationMaxHeight)
                .padding(IDVLayout.Spacing.heroPadding)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius + IDVLayout.Radius.heroPanelExtra)
                        .fill(Color(red: IDVLayout.Fill.heroPanel.red, green: IDVLayout.Fill.heroPanel.green, blue: IDVLayout.Fill.heroPanel.blue))
                )
                .accessibilityHidden(true)
        } else {
            ZStack {
                Circle()
                    .fill(theme.primary.opacity(IDVLayout.Opacity.tint))
                    .frame(width: IDVLayout.Size.heroCircle, height: IDVLayout.Size.heroCircle)
                Image(systemName: systemName)
                    .font(.system(size: IDVLayout.IconSize.hero, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.primary)
            }
            .accessibilityHidden(true)
        }
    }

    private func primaryButton(titleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titleKey, bundle: .module)
                .font(theme.font(.button))
                .foregroundStyle(theme.onPrimary)
                .frame(maxWidth: .infinity, minHeight: IDVLayout.Size.buttonHeight)
                .background(theme.primary, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
        }
    }

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
                Text(IDVStrings.securedBadge, bundle: .module)
            } icon: {
                Image(systemName: IDVIcon.securedBadge)
            }
            .font(theme.font(.caption))
            .foregroundStyle(theme.textSecondary.opacity(IDVLayout.Opacity.poweredBy))
            .padding(.top, IDVLayout.Spacing.tiny)
        }
    }
}

// MARK: - Document-kind presentation (UI layer only)

extension IDVVerificationStep.DocumentKind {
    /// SF Symbol shown on the document-selection card.
    fileprivate var idvIconName: String {
        switch self {
        case .passport: IDVIcon.Document.passport
        case .idCard: IDVIcon.Document.idCard
        case .residencePermit: IDVIcon.Document.residencePermit
        case .any: IDVIcon.Document.any
        }
    }

    /// Card title.
    fileprivate var idvTitleKey: LocalizedStringKey {
        switch self {
        case .passport: IDVStrings.DocumentKind.passportTitle
        case .idCard: IDVStrings.DocumentKind.idCardTitle
        case .residencePermit: IDVStrings.DocumentKind.residencePermitTitle
        case .any: IDVStrings.DocumentKind.anyTitle
        }
    }

    /// Card supporting line.
    fileprivate var idvSubtitleKey: LocalizedStringKey {
        switch self {
        case .passport: IDVStrings.DocumentKind.passportSubtitle
        case .idCard: IDVStrings.DocumentKind.idCardSubtitle
        case .residencePermit: IDVStrings.DocumentKind.residencePermitSubtitle
        case .any: IDVStrings.DocumentKind.anySubtitle
        }
    }

    /// Inline noun phrase for mismatch copy, e.g. "a passport".
    fileprivate var idvNoun: String {
        switch self {
        case .passport: IDVStrings.DocumentKind.passportNoun
        case .idCard: IDVStrings.DocumentKind.idCardNoun
        case .residencePermit: IDVStrings.DocumentKind.residencePermitNoun
        case .any: IDVStrings.DocumentKind.anyNoun
        }
    }
}

#if DEBUG
    extension UIImage {
        /// The image redrawn with `.up` orientation so its `CGImage` has upright
        /// pixels for Vision (library photos carry EXIF rotation).
        fileprivate var idvUprightCGImage: CGImage? {
            guard imageOrientation != .up else { return cgImage }
            UIGraphicsBeginImageContextWithOptions(size, false, scale)
            draw(in: CGRect(origin: .zero, size: size))
            let normalized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return normalized?.cgImage
        }
    }
#endif
