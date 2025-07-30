//
//  VerifIDExampleApp.swift
//  VerifIDExample
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import OSLog
import SwiftUI
import VerifID

/// Example-app logger, same subsystem as the SDK so it shows in one stream.
let exampleLog = Logger(subsystem: "dev.verifid", category: "example")

@main
struct VerifIDExampleApp: App {
    init() {
        VIDLog.isEnabled = true // Console.app, subsystem dev.verifid
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var showFlow = false
    @State private var showScanner = false
    @State private var lastResult = "No verification run yet."
    @State private var scannedMRZ = ""
    @State private var mockOutput = ""
    @State private var lastMRZ: VIDMRZData?
    @State private var nfcOutput = ""
    @State private var chipFace: UIImage?
    @State private var showFaceCapture = false
    @State private var faceOutput = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showFlow = true
                    } label: {
                        Label("Verify an ID document", systemImage: "person.text.rectangle.fill")
                            .font(.headline)
                    }
                    if lastResult != "No verification run yet." {
                        Text(lastResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Complete flow")
                } footer: {
                    Text("The drop-in VIDVerificationFlowView: intro → scan MRZ → read the NFC chip → result. Works with passports (TD3) and ID cards / residence permits (TD1/TD2) — the layout is auto-detected. Everything runs on-device. Device only (NFC can't run in the simulator).")
                }

                Section {
                    Button("Scan MRZ only") { showScanner = true }
                    if !scannedMRZ.isEmpty {
                        Text(scannedMRZ)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    // Once the standalone scanner has an MRZ, the standalone NFC
                    // reader can use it — this shows devs the two pieces composing.
                    if lastMRZ != nil {
                        Button("Read chip via NFC") { Task { await readChip() } }
                    }
                    if let chipFace {
                        Image(uiImage: chipFace)
                            .resizable().scaledToFit()
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    if !nfcOutput.isEmpty {
                        Text(nfcOutput)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    // Standalone face match: once the chip gave us a portrait, run
                    // the liveness + face-match component against it.
                    if chipFace != nil {
                        Button("Match face to chip photo") { showFaceCapture = true }
                    }
                    if !faceOutput.isEmpty {
                        Text(faceOutput)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Button("Parse specimen MRZ + mock chip read") {
                        Task { await runHeadlessDemo() }
                    }
                    if !mockOutput.isEmpty {
                        Text(mockOutput)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Developer building blocks")
                } footer: {
                    Text("Individual SDK pieces you can compose yourself: the standalone MRZ scanner, the standalone NFC chip reader, and the headless (no camera / no NFC) parsing + mock-read APIs.")
                }
            }
            .navigationTitle("VerifID Example")
            .sheet(isPresented: $showFlow) {
                VIDVerificationFlowView(configuration: flowConfiguration) { result in
                    switch result {
                    case .verified(let outcome):
                        lastResult = "Verified \(outcome.document.mrz.surname)"
                    case .failed(let error):
                        lastResult = "Failed: \(error.localizedDescription)"
                    case .cancelled:
                        lastResult = "Cancelled."
                    }
                    showFlow = false
                }
            }
            #if DEBUG
                // Design-review harness: `SIMCTL_CHILD_VID_DEBUG_STEP=chipGuidance
                // xcrun simctl launch …` opens the flow straight at a screen so the
                // camera/NFC-gated screens can be reviewed in the Simulator.
                .fullScreenCover(isPresented: .constant(
                    ProcessInfo.processInfo.environment["VID_DEBUG_STEP"] != nil
                )) {
                    VIDVerificationFlowView(
                        configuration: flowConfiguration,
                        debugStartAt: ProcessInfo.processInfo.environment["VID_DEBUG_STEP"] ?? "intro"
                    ) { _ in }
                }
            #endif
            .fullScreenCover(isPresented: $showScanner) {
                VIDMRZScannerView { mrz in
                    scannedMRZ = "\(mrz.surname), \(mrz.givenNames)\n\(mrz.documentNumber) · \(mrz.nationality)"
                    lastMRZ = mrz
                    showScanner = false
                } onError: { error in
                    scannedMRZ = "Error: \(error.localizedDescription)"
                    showScanner = false
                } onClose: {
                    showScanner = false
                }
            }
            .fullScreenCover(isPresented: $showFaceCapture) {
                if let reference = chipFace?.cgImage {
                    VIDFaceCaptureView(reference: reference) { liveness, match in
                        faceOutput = """
                        Liveness: \(liveness.passed ? "passed" : "failed") (\(liveness.challengesCompleted.joined(separator: ", ")))
                        Face match: \(match.isMatch ? "✓ match" : "✗ no match") · similarity \(String(format: "%.2f", match.similarity))
                        """
                        showFaceCapture = false
                    } onCancel: {
                        showFaceCapture = false
                    }
                }
            }
        }
    }

    /// The drop-in flow's configuration, wiring in the bundled CSCA trust store
    /// so chain-of-trust runs. Without this the flow defaults to `.integrityOnly`
    /// and reports chain-of-trust as `notPerformed`.
    private var flowConfiguration: VIDConfiguration {
        VIDConfiguration(
            // Offer all three document types, so the flow shows its
            // document-selection screen before scanning. Set a single kind (or
            // leave the default `[.any]`) to skip the picker and auto-detect.
            mrz: VIDMRZConfiguration(allowedDocuments: [.passport, .idCard, .residencePermit]),
            nfc: VIDNFCConfiguration(passiveAuthentication: passiveAuthConfig()),
            // Lets us test the face match against a library photo (DEBUG only).
            face: VIDFaceConfiguration(allowsDebugPhotoMatch: true)
            // Hero illustrations ship inside the SDK, so nothing to configure here —
            // the flow looks finished out of the box. Override via
            // `ui.illustrations` only to brand it.
        )
    }

    /// Loads a bundled CSCA master list if one is present, so chain-of-trust can
    /// run. Drop a `GermanMasterList` master-list file (any extension) into the
    /// app bundle — see the README. Falls back to integrity-only if absent.
    private func passiveAuthConfig() -> VIDNFCConfiguration.PassiveAuthentication {
        let candidates = ["ml", "mls", "bin", "der", "pem"].compactMap {
            Bundle.main.url(forResource: "GermanMasterList", withExtension: $0)
        }
        guard let url = candidates.first, let data = try? Data(contentsOf: url) else {
            exampleLog.error("No GermanMasterList.* in bundle → integrity-only (chain-of-trust will be notPerformed)")
            return .integrityOnly
        }
        let store = VIDTrustStore(masterListCMS: data)
        exampleLog.log("Loaded \(url.lastPathComponent) (\(data.count) bytes) → \(store.anchorsDER.count) CSCA anchor(s)")
        return store.anchorsDER.isEmpty ? .integrityOnly : .enabled(cscaTrustStore: store)
    }

    /// Standalone NFC reader building block: reads the chip using the MRZ from
    /// the standalone scanner, with the same trust store as the drop-in flow.
    private func readChip() async {
        guard let mrz = lastMRZ else { return }
        nfcOutput = "Starting NFC read…"
        let key = VIDMRZKey(
            documentNumber: mrz.documentNumber,
            birthDate: mrz.birthDate,
            expiryDate: mrz.expiryDate
        )
        do {
            let passport = try await VIDPassportReader(configuration: flowConfiguration.nfc).read(mrzKey: key)
            let pa = passport.authenticity.passiveAuthentication
            chipFace = passport.faceImageData.flatMap(UIImage.init(data:))
            nfcOutput = """
            Chip read OK ✓
            \(passport.mrz.givenNames) \(passport.mrz.surname)
            Groups: \(passport.dataGroupsRead.map(\.rawValue).joined(separator: ", "))
            Data integrity: \(pa.dataIntegrity)
            Chain of trust: \(pa.chainOfTrust)
            Active auth: \(passport.authenticity.activeAuthentication)
            """
        } catch {
            chipFace = nil
            nfcOutput = "NFC read failed: \(error.localizedDescription)"
        }
    }

    private func runHeadlessDemo() async {
        do {
            let mrz = try VIDMRZParser.parseTD3(
                line1: "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
                line2: "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
            )
            let key = VIDMRZKey(
                documentNumber: mrz.documentNumber,
                birthDate: mrz.birthDate,
                expiryDate: mrz.expiryDate
            )
            let passport = try await VIDMockPassportReader().read(mrzKey: key)
            mockOutput = """
            MRZ: \(mrz.givenNames) \(mrz.surname) (\(mrz.nationality))
            BAC key seed: \(try key.seedString())
            Mock chip: \(passport.dataGroupsRead.map(\.rawValue).joined(separator: ", "))
            """
        } catch {
            mockOutput = "Error: \(error.localizedDescription)"
        }
    }
}
