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
        case documentSelection
        case documentScanGuidance
        case documentIssue
        case chipGuidance
        case readingChip
        case faceIntro
        case result
    }

    /// Resolves a hero illustration: a developer override, else the illustration
    /// VerifID ships in its own bundle, else `nil` (the screen shows a symbol).
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
        case notAccepted(detected: VIDVerificationStep.DocumentKind)
        /// The detected type is accepted but differs from what the user picked.
        case pickMismatch(detected: VIDVerificationStep.DocumentKind,
                          picked: VIDVerificationStep.DocumentKind)
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
    /// The document type the user picked on the selection screen, when the flow
    /// offers a choice. Drives the scanner reticle; recognition auto-detects.
    @State private var selectedDocumentKind: VIDVerificationStep.DocumentKind?
    /// A detected document-type problem, shown on the `.documentIssue` screen.
    @State private var documentIssue: DocumentIssue?

    public init(
        configuration: VIDConfiguration = .default,
        onCompletion: @escaping (VIDVerificationResult) -> Void
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
    }

    #if DEBUG
        /// DEBUG-only: opens the flow at a specific screen with mock data so the
        /// static screens can be reviewed in the Simulator (which can't run the
        /// camera or NFC). Compiled out of release builds; not shipping API.
        public init(
            configuration: VIDConfiguration = .default,
            debugStartAt screen: String,
            onCompletion: @escaping (VIDVerificationResult) -> Void
        ) {
            self.configuration = configuration
            self.onCompletion = onCompletion
            _scannedMRZ = State(initialValue: VIDMRZData(
                format: .td3, documentType: "P", issuingCountry: "USA",
                documentNumber: "X1234567", nationality: "USA", surname: "DOE",
                givenNames: "JANE", birthDate: "900101", expiryDate: "300101", sex: "F"
            ))
            let step: Step = switch screen {
            case "documentSelection": .documentSelection
            case "documentScanGuidance": .documentScanGuidance
            case "chipGuidance": .chipGuidance
            case "faceIntro": .faceIntro
            case "result": .result
            default: .intro
            }
            _step = State(initialValue: step)
        }
    #endif

    /// The MRZ scanner config, with the document kind taken from the flow's
    /// `documentScan` step so the reticle matches what's being scanned.
    private var scannerConfiguration: VIDMRZConfiguration {
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
    private func routeAfterScan(_ mrz: VIDMRZData) {
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
                VIDMRZScannerView(configuration: scannerConfiguration) { mrz in
                    scannedMRZ = mrz
                    isScanning = false
                    routeAfterScan(mrz)
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
                        faceMatch = match
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
        VStack(spacing: VIDLayout.Spacing.title) {
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

            screenHeader(VIDStrings.Intro.title, VIDStrings.Intro.subtitle)

            if let logoData = configuration.ui.branding.logoImageData,
               let uiImage = UIImage(data: logoData) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFit()
                    .frame(width: VIDLayout.Size.logo, height: VIDLayout.Size.logo)
                    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
            } else {
                heroSymbol(VIDIcon.intro,
                           illustration: heroData(configuration.ui.illustrations.intro, default: "vid-illus-intro"))
            }

            Spacer()

            primaryButton(titleKey: VIDStrings.Button.start) { beginDocumentCapture() }
            secondaryButton(titleKey: VIDStrings.Button.cancel) { onCompletion(.cancelled) }
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

            VStack(spacing: VIDLayout.Spacing.small) {
                Text(VIDStrings.DocumentSelection.title, bundle: .module)
                    .font(theme.font(.largeTitle))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(VIDStrings.DocumentSelection.subtitle, bundle: .module)
                    .font(theme.font(.body))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: VIDLayout.Spacing.medium) {
                ForEach(configuration.mrz.selectableDocuments, id: \.self) { kind in
                    documentOptionRow(kind)
                }
            }
            .padding(.top, VIDLayout.Spacing.small)

            Spacer()

            secondaryButton(titleKey: VIDStrings.Button.cancel) { onCompletion(.cancelled) }
            poweredByBadge
        }
        .padding(theme.screenPadding)
    }

    private func documentOptionRow(_ kind: VIDVerificationStep.DocumentKind) -> some View {
        Button {
            selectedDocumentKind = kind
            step = .documentScanGuidance
        } label: {
            HStack(spacing: VIDLayout.Spacing.large) {
                Image(systemName: kind.vidIconName)
                    .font(.system(size: VIDLayout.IconSize.row))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.primary)
                    .frame(width: VIDLayout.Size.rowIconSlot)

                VStack(alignment: .leading, spacing: VIDLayout.Spacing.micro) {
                    Text(kind.vidTitleKey, bundle: .module)
                        .font(theme.font(.headline))
                        .foregroundStyle(theme.textPrimary)
                    Text(kind.vidSubtitleKey, bundle: .module)
                        .font(theme.font(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
                .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: VIDIcon.chevron)
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(theme.screenPadding * VIDLayout.Scale.rowPaddingFactor)
            .frame(maxWidth: .infinity)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .strokeBorder(theme.textSecondary.opacity(VIDLayout.Opacity.tint))
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

            screenHeader(VIDStrings.ScanGuidance.title, VIDStrings.ScanGuidance.subtitle)

            heroSymbol(VIDIcon.documentScan,
                       illustration: heroData(configuration.ui.illustrations.documentScan, default: "vid-illus-scan"))

            chipRequirementNote

            Spacer()

            primaryButton(titleKey: VIDStrings.Button.scanDocument) { isScanning = true }
            secondaryButton(titleKey: VIDStrings.Button.cancel) { onCompletion(.cancelled) }
        }
        .padding(theme.screenPadding)
    }

    /// Educates the user that the document needs a readable NFC chip, showing the
    /// "chip inside" symbol to look for. Copy adapts to the chosen document kind —
    /// passports print the symbol on the cover; cards vary front/back.
    private var chipRequirementNote: some View {
        HStack(spacing: VIDLayout.Spacing.row) {
            VIDChipSymbol(tint: theme.primary)
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
            VIDStrings.ScanGuidance.chipNotePassport
        case .idCard, .residencePermit:
            VIDStrings.ScanGuidance.chipNoteCard
        default:
            VIDStrings.ScanGuidance.chipNoteGeneric
        }
    }

    // MARK: Document issue (detected type not accepted, or ≠ the user's pick)

    /// Shown when the scanned MRZ's detected document type isn't accepted, or
    /// differs from what the user picked. The MRZ is the source of truth, so we
    /// surface the mismatch rather than silently proceeding with the wrong label.
    private var documentIssueScreen: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            Image(systemName: VIDIcon.warning)
                .font(.system(size: VIDLayout.IconSize.warning))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.warning)

            switch documentIssue {
            case let .notAccepted(detected):
                Text(VIDStrings.DocumentIssue.notAcceptedTitle, bundle: .module)
                    .font(theme.font(.largeTitle))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(verbatim: VIDStrings.DocumentIssue.notAcceptedBody(detected.vidNoun))
                    .font(theme.font(.body))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)

                Spacer()

                if configuration.mrz.offersDocumentChoice {
                    primaryButton(titleKey: VIDStrings.Button.chooseType) {
                        documentIssue = nil
                        step = .documentSelection
                    }
                    secondaryButton(titleKey: VIDStrings.Button.scanAgain) { retryScan() }
                } else {
                    primaryButton(titleKey: VIDStrings.Button.scanAgain) { retryScan() }
                }
                secondaryButton(titleKey: VIDStrings.Button.cancel) { onCompletion(.cancelled) }

            case let .pickMismatch(detected, picked):
                Text(verbatim: VIDStrings.DocumentIssue.PickMismatch.title(detected.vidNoun))
                    .font(theme.font(.largeTitle))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(verbatim: VIDStrings.DocumentIssue.PickMismatch.body(picked: picked.vidNoun, detected: detected.vidNoun))
                    .font(theme.font(.body))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)

                Spacer()

                primaryButton(titleKey: VIDStrings.Button.proceed) {
                    // Trust the detection over the pick.
                    selectedDocumentKind = detected
                    documentIssue = nil
                    step = .chipGuidance
                }
                secondaryButton(titleKey: VIDStrings.Button.chooseDifferent) {
                    documentIssue = nil
                    step = .documentSelection
                }
                secondaryButton(titleKey: VIDStrings.Button.scanAgain) { retryScan() }

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
            Spacer()

            screenHeader(VIDStrings.ChipGuidance.title, VIDStrings.ChipGuidance.subtitle)

            // The chip screen is the one place a motion tutorial measurably helps
            // (users have no mental model of the antenna). Default to a native
            // animated tap; a developer-supplied illustration overrides it.
            if let chipIllustration = configuration.ui.illustrations.chipGuidance {
                heroSymbol(VIDIcon.chipGuidance, illustration: chipIllustration)
            } else {
                VIDNFCTapAnimation(tint: theme.primary)
            }

            VStack(alignment: .leading, spacing: VIDLayout.Spacing.medium) {
                guidanceRow(VIDIcon.restPhone, VIDStrings.ChipGuidance.rowRest)
                guidanceRow(VIDIcon.holdStill, VIDStrings.ChipGuidance.rowHoldStill)
                guidanceRow(VIDIcon.phoneCase, VIDStrings.ChipGuidance.rowCase)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))

            Spacer()

            primaryButton(titleKey: VIDStrings.Button.scanChip) {
                if let mrz = scannedMRZ {
                    startChipRead(mrz: mrz)
                }
            }
            secondaryButton(titleKey: VIDStrings.Button.cancel) { onCompletion(.cancelled) }
        }
        .padding(theme.screenPadding)
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
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(theme.primary)
            Text(VIDStrings.ReadingChip.title, bundle: .module)
                .font(theme.font(.headline))
                .foregroundStyle(theme.textPrimary)
            Text(VIDStrings.ReadingChip.subtitle, bundle: .module)
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
    private var faceIntro: some View {
        VStack(spacing: theme.screenPadding) {
            Spacer()

            screenHeader(VIDStrings.FaceIntro.title, VIDStrings.FaceIntro.subtitle)

            if let reference = referenceFace {
                Image(decorative: reference, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: VIDLayout.Size.facePortraitWidth, height: VIDLayout.Size.facePortraitHeight)
                    .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).stroke(theme.primary.opacity(VIDLayout.Opacity.subtle)))
            } else {
                heroSymbol(VIDIcon.faceIntro,
                           illustration: heroData(configuration.ui.illustrations.faceIntro, default: "vid-illus-face"))
            }

            Spacer()
            primaryButton(titleKey: VIDStrings.Button.startFaceScan) { isCapturingFace = true }
            secondaryButton(titleKey: VIDStrings.Button.skip) { step = .result }

            #if DEBUG
                // Developer testing: replace the reference (document) photo with a
                // library image, so the live face scan matches against THAT instead of
                // the chip photo. Compiled out of release builds.
                if configuration.face.allowsDebugPhotoMatch {
                    // Hoist the @MainActor-isolated values here (this builder body is
                    // MainActor); the PhotosPicker label closure is not MainActor-
                    // isolated under strict concurrency, so it may only capture these
                    // Sendable copies — not `theme`/`debugReferenceOverride` directly.
                    let pickerLabel = debugReferenceOverride == nil
                        ? VIDStrings.Debug.usePhoto
                        : VIDStrings.Debug.photoSet
                    let captionFont = theme.font(.caption)
                    let captionColor = theme.textSecondary
                    PhotosPicker(selection: $debugPhotoItem, matching: .images) {
                        Label(pickerLabel, systemImage: VIDIcon.debugPhoto)
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
                    if let data, let cgImage = UIImage(data: data)?.vidUprightCGImage {
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
                        .frame(width: VIDLayout.Size.resultPhotoWidth, height: VIDLayout.Size.resultPhotoHeight)
                        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                }
                Text(verbatim: "\(passport.mrz.givenNames) \(passport.mrz.surname)")
                    .font(theme.font(.title))
                    .foregroundStyle(theme.textPrimary)

                if configuration.ui.showDataReview {
                    VStack(alignment: .leading, spacing: VIDLayout.Spacing.medium) {
                        reviewRow(VIDStrings.Result.Row.document, passport.mrz.documentNumber)
                        reviewRow(VIDStrings.Result.Row.nationality, passport.mrz.nationality)
                        reviewRow(VIDStrings.Result.Row.sex, passport.mrz.sexDescription ?? "")
                        reviewRow(VIDStrings.Result.Row.dateOfBirth, passport.mrz.formattedDateOfBirth ?? passport.mrz.birthDate)
                        reviewRow(VIDStrings.Result.Row.expiry, passport.mrz.formattedDateOfExpiry ?? passport.mrz.expiryDate,
                                  valueColor: passport.mrz.isExpired ? theme.error : nil)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
                }

                // The chip is access-controlled by the scanned MRZ, so a
                // successful read proves the scanned document matches the chip.
                if mrzMatchesChip {
                    badgeLabel(VIDStrings.Badge.mrzMatchesChip, systemImage: VIDIcon.mrzMatchesChip, color: theme.success)
                }
                authenticityBadge(passport.authenticity.passiveAuthentication)
                antiCloneBadge(passport.authenticity)
                if let faceMatch {
                    faceMatchBadge(faceMatch)
                }

                Spacer()
                primaryButton(titleKey: VIDStrings.Button.done) {
                    onCompletion(.verified(VIDVerificationOutcome(
                        document: passport, liveness: liveness, faceMatch: faceMatch
                    )))
                }
            } else {
                Spacer()
                Image(systemName: VIDIcon.warning)
                    .font(.largeTitle)
                    .foregroundStyle(theme.error)
                Text(VIDStrings.Result.couldNotRead, bundle: .module)
                    .font(theme.font(.title))
                    .foregroundStyle(theme.textPrimary)
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(theme.font(.body))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                primaryButton(titleKey: VIDStrings.Button.tryAgain) { step = .intro }
                secondaryButton(titleKey: VIDStrings.Button.cancel) { onCompletion(.cancelled) }
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
                    if case .cancelledByUser = error {
                        step = .chipGuidance
                    } else {
                        errorMessage = error.errorDescription; step = .result
                    }
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
            badgeLabel(VIDStrings.Badge.chipVerified, systemImage: VIDIcon.chipVerified, color: theme.success)
        case (.passed, _):
            // Data is intact and signed, but the issuer chain wasn't fully
            // confirmed (e.g. that country's CSCA isn't in the trust store).
            // That's a developer/integration concern, not something to alarm an
            // end user with — only surface it in detail mode, and render nothing
            // (not an empty container that would leave a gap) otherwise. The
            // specific reason (e.g. "add the CSCA for [CN=…]") stays on the result.
            if showDetails {
                VStack(spacing: VIDLayout.Spacing.tiny) {
                    badgeLabel(VIDStrings.Badge.chipDataIntact, systemImage: VIDIcon.chipDataIntact, color: theme.primary)
                    detailText(result.chainOfTrust.reason)
                }
            }
        default:
            // Data integrity itself failed — a genuine problem worth surfacing.
            VStack(spacing: VIDLayout.Spacing.tiny) {
                badgeLabel(VIDStrings.Badge.chipUnverifiable, systemImage: VIDIcon.chipUnverifiable, color: theme.warning)
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
    private func antiCloneBadge(_ result: VIDChipAuthenticityResult) -> some View {
        if result.chipAuthentication.isPassed || result.activeAuthentication.isPassed {
            badgeLabel(VIDStrings.Badge.genuineChip, systemImage: VIDIcon.genuineChip, color: theme.success)
        } else if case .failed = result.chipAuthentication {
            badgeLabel(VIDStrings.Badge.chipAuthFailed, systemImage: VIDIcon.chipAuthFailed, color: theme.error)
        } else if case .failed = result.activeAuthentication {
            badgeLabel(VIDStrings.Badge.chipAuthFailed, systemImage: VIDIcon.chipAuthFailed, color: theme.error)
        }
    }

    /// Shows the face-match verdict with the two faces side by side.
    private func faceMatchBadge(_ result: VIDFaceMatchResult) -> some View {
        VStack(spacing: VIDLayout.Spacing.small) {
            HStack(spacing: VIDLayout.Spacing.title) {
                thumbnail(result.referenceImageData)
                Image(systemName: result.isMatch ? VIDIcon.faceMatch : VIDIcon.faceMismatch)
                    .foregroundStyle(result.isMatch ? theme.success : theme.error)
                thumbnail(result.liveImageData)
            }
            badgeLabel(
                result.isMatch ? VIDStrings.Badge.faceMatches : VIDStrings.Badge.faceMismatch,
                systemImage: result.isMatch ? VIDIcon.faceMatchBadge : VIDIcon.faceMismatchBadge,
                color: result.isMatch ? theme.success : theme.error
            )
            if configuration.ui.showsSecurityDetails {
                detailText(VIDStrings.Badge.similarityDetail(result.similarity, threshold: result.thresholdUsed))
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: VIDLayout.Size.matchThumbWidth, height: VIDLayout.Size.matchThumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: VIDLayout.Radius.matchThumb))
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
                Spacer(minLength: VIDLayout.Spacing.medium)
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
                .frame(maxWidth: VIDLayout.Size.illustrationMaxWidth, maxHeight: VIDLayout.Size.illustrationMaxHeight)
                .padding(VIDLayout.Spacing.heroPadding)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius + VIDLayout.Radius.heroPanelExtra)
                        .fill(Color(red: VIDLayout.Fill.heroPanel.red, green: VIDLayout.Fill.heroPanel.green, blue: VIDLayout.Fill.heroPanel.blue))
                )
                .accessibilityHidden(true)
        } else {
            ZStack {
                Circle()
                    .fill(theme.primary.opacity(VIDLayout.Opacity.tint))
                    .frame(width: VIDLayout.Size.heroCircle, height: VIDLayout.Size.heroCircle)
                Image(systemName: systemName)
                    .font(.system(size: VIDLayout.IconSize.hero, weight: .regular))
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
                .frame(maxWidth: .infinity, minHeight: VIDLayout.Size.buttonHeight)
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
                Text(VIDStrings.securedBadge, bundle: .module)
            } icon: {
                Image(systemName: VIDIcon.securedBadge)
            }
            .font(theme.font(.caption))
            .foregroundStyle(theme.textSecondary.opacity(VIDLayout.Opacity.poweredBy))
            .padding(.top, VIDLayout.Spacing.tiny)
        }
    }
}

// MARK: - Document-kind presentation (UI layer only)

extension VIDVerificationStep.DocumentKind {
    /// SF Symbol shown on the document-selection card.
    fileprivate var vidIconName: String {
        switch self {
        case .passport: VIDIcon.Document.passport
        case .idCard: VIDIcon.Document.idCard
        case .residencePermit: VIDIcon.Document.residencePermit
        case .any: VIDIcon.Document.any
        }
    }

    /// Card title.
    fileprivate var vidTitleKey: LocalizedStringKey {
        switch self {
        case .passport: VIDStrings.DocumentKind.passportTitle
        case .idCard: VIDStrings.DocumentKind.idCardTitle
        case .residencePermit: VIDStrings.DocumentKind.residencePermitTitle
        case .any: VIDStrings.DocumentKind.anyTitle
        }
    }

    /// Card supporting line.
    fileprivate var vidSubtitleKey: LocalizedStringKey {
        switch self {
        case .passport: VIDStrings.DocumentKind.passportSubtitle
        case .idCard: VIDStrings.DocumentKind.idCardSubtitle
        case .residencePermit: VIDStrings.DocumentKind.residencePermitSubtitle
        case .any: VIDStrings.DocumentKind.anySubtitle
        }
    }

    /// Inline noun phrase for mismatch copy, e.g. "a passport".
    fileprivate var vidNoun: String {
        switch self {
        case .passport: VIDStrings.DocumentKind.passportNoun
        case .idCard: VIDStrings.DocumentKind.idCardNoun
        case .residencePermit: VIDStrings.DocumentKind.residencePermitNoun
        case .any: VIDStrings.DocumentKind.anyNoun
        }
    }
}

#if DEBUG
    extension UIImage {
        /// The image redrawn with `.up` orientation so its `CGImage` has upright
        /// pixels for Vision (library photos carry EXIF rotation).
        fileprivate var vidUprightCGImage: CGImage? {
            guard imageOrientation != .up else { return cgImage }
            UIGraphicsBeginImageContextWithOptions(size, false, scale)
            draw(in: CGRect(origin: .zero, size: size))
            let normalized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return normalized?.cgImage
        }
    }
#endif
