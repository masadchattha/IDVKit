//
//  VIDMRZScanner.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

@preconcurrency import AVFoundation
import Foundation
import OSLog
import UIKit
import VerifIDCore
import Vision

/// Live camera MRZ scanner: AVFoundation capture + the Vision framework's
/// `VNRecognizeTextRequest`. No Tesseract, no third-party OCR.
///
/// A frame is accepted only when a candidate MRZ passes **all** ICAO 9303
/// check digits (``VIDMRZParser``), so a single mis-read character can never
/// produce a wrong result — the scanner simply keeps looking.
///
/// Use the drop-in ``VIDMRZScannerView`` for a complete UI, or drive this
/// class directly with your own preview:
///
/// ```swift
/// let scanner = VIDMRZScanner()
/// myView.layer.addSublayer(scanner.previewLayer)
/// scanner.onResult = { result in ... }   // delivered on the main thread
/// scanner.start()
/// ```
public final class VIDMRZScanner: NSObject, @unchecked Sendable {

    // MARK: Public surface

    /// Delivered once on the main thread with the first checksum-valid MRZ.
    public var onResult: (@MainActor (VIDMRZData) -> Void)?

    /// Camera/permission problems, delivered on the main thread.
    public var onError: (@MainActor (VIDError) -> Void)?

    /// Attach this to your view hierarchy to show the camera feed.
    public let previewLayer: AVCaptureVideoPreviewLayer

    public override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    /// Requests camera permission if needed, configures the session once,
    /// and starts the capture. Safe to call repeatedly.
    public func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.requestAccessAndConfigure()
        }
    }

    /// Stops the capture. The scanner can be restarted with ``start()``.
    public func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Toggles the torch for low-light scanning.
    /// - Returns: The new torch state (`false` when unavailable).
    @discardableResult
    public func toggleTorch() -> Bool {
        guard let device = videoDevice, device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
            return device.torchMode == .on
        } catch {
            Logger.mrz.vidError("Torch toggle failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Capture pipeline (session-queue confined)

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "dev.verifid.mrz.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var videoDevice: AVCaptureDevice?
    private var isConfigured = false
    private var didDeliverResult = false

    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            Logger.mrz.vidDebug("Requesting camera permission")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.sessionQueue.async {
                    granted ? self?.configureAndRun() : self?.deliverError(.cameraPermissionDenied)
                }
            }
        default:
            deliverError(.cameraPermissionDenied)
        }
    }

    private func configureAndRun() {
        if !isConfigured {
            session.beginConfiguration()
            session.sessionPreset = .hd1920x1080

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                session.commitConfiguration()
                deliverError(.nfcSessionFailed(detail: "No back camera available"))
                return
            }
            session.addInput(input)
            videoDevice = device

            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                deliverError(.nfcSessionFailed(detail: "Cannot add video output"))
                return
            }
            session.addOutput(videoOutput)
            if let connection = videoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    connection.videoRotationAngle = 90 // portrait
                } else {
                    connection.videoOrientation = .portrait
                }
            }

            // MRZ is small text — a close focus range speeds up lock-on.
            if let device = videoDevice, device.isAutoFocusRangeRestrictionSupported {
                try? device.lockForConfiguration()
                device.autoFocusRangeRestriction = .near
                device.unlockForConfiguration()
            }
            session.commitConfiguration()
            isConfigured = true
            Logger.mrz.vidDebug("Camera configured (\(session.sessionPreset.rawValue)); starting MRZ scan")
        }
        didDeliverResult = false
        frameCount = 0
        if !session.isRunning { session.startRunning() }
    }

    // MARK: Recognition (session-queue confined)

    private var frameCount = 0

    private func recognize(in pixelBuffer: CVPixelBuffer) {
        guard !didDeliverResult else { return }
        frameCount += 1

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self else { return }
            if let error {
                Logger.mrz.vidError("Vision text request failed: \(error.localizedDescription)")
                return
            }
            guard !self.didDeliverResult,
                  let observations = request.results as? [VNRecognizedTextObservation] else { return }

            // Sort top-to-bottom (Vision's origin is bottom-left → larger y is higher).
            let rawLines = observations
                .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                .compactMap { $0.topCandidates(1).first?.string }

            let candidates = rawLines.compactMap(Self.normalizeMRZLine)

            if !rawLines.isEmpty {
                Logger.mrz.vidDebug("OCR saw \(rawLines.count) line(s), \(candidates.count) MRZ-shaped")
                for line in candidates { Logger.mrz.vidDebug("  candidate: \(line)") }
            }

            if let mrz = Self.assembleMRZ(from: candidates) {
                self.didDeliverResult = true
                Logger.mrz.vidDebug("✓ MRZ accepted (\(mrz.format.rawValue)) for document \(mrz.documentNumber)")
                DispatchQueue.main.async { [onResult] in
                    MainActor.assumeIsolated { onResult?(mrz) }
                }
                return
            }
        }
        // `.accurate` is essential for the OCR-B passport font; `.fast` misreads
        // enough characters that the check digits never validate.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // MRZ is not natural language

        // Scan the full frame. Confining recognition to the on-screen MRZ strip
        // proved unreliable — the preview-layer→Vision coordinate conversion can
        // produce an out-of-bounds region (Vision then rejects every frame) — and
        // full-frame OCR reads the MRZ reliably and instantly. The strip stays a
        // visual guide only; the checksum-gated parse ignores any non-MRZ text.
        if frameCount == 1 { Logger.mrz.vidDebug("Recognizing MRZ (accurate, full-frame)…") }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            Logger.mrz.vidError("Vision perform failed: \(error.localizedDescription)")
        }
    }

    /// Normalizes an OCR line into candidate MRZ form; returns `nil` unless the
    /// result is a full-width MRZ line from the MRZ character set — 30 (TD1),
    /// 36 (TD2) or 44 (TD3) characters.
    static func normalizeMRZLine(_ raw: String) -> String? {
        let cleaned = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "«", with: "<<")
            .replacingOccurrences(of: "≪", with: "<<")
            .uppercased()
        guard [30, 36, 44].contains(cleaned.count),
              cleaned.allSatisfy({ $0 == "<" || ($0.isASCII && ($0.isNumber || ("A"..."Z").contains($0))) })
        else { return nil }
        return cleaned
    }

    /// Assembles a checksum-valid MRZ from the OCR'd candidate lines, trying each
    /// supported layout (TD3 44×2, TD2 36×2, TD1 30×3). The data line of each
    /// grouping gets field-aware OCR digit correction before the parse. Returns
    /// `nil` until a layout parses with all check digits valid.
    static func assembleMRZ(from candidates: [String]) -> VIDMRZData? {
        // TD3 — two adjacent 44-character lines.
        for i in candidates.indices.dropLast()
        where candidates[i].count == 44 && candidates[i + 1].count == 44 {
            if let mrz = try? VIDMRZParser.parseTD3(
                line1: candidates[i], line2: correctTD3DataLine(candidates[i + 1])) { return mrz }
        }
        // TD2 — two adjacent 36-character lines.
        for i in candidates.indices.dropLast()
        where candidates[i].count == 36 && candidates[i + 1].count == 36 {
            if let mrz = try? VIDMRZParser.parseTD2(
                line1: candidates[i], line2: correctTD2DataLine(candidates[i + 1])) { return mrz }
        }
        // TD1 — three adjacent 30-character lines.
        for i in candidates.indices where i + 2 < candidates.count
        && candidates[i].count == 30 && candidates[i + 1].count == 30 && candidates[i + 2].count == 30 {
            if let mrz = try? VIDMRZParser.parseTD1(
                line1: candidates[i], line2: correctTD1DataLine(candidates[i + 1]),
                line3: candidates[i + 2]) { return mrz }
        }
        return nil
    }

    /// Coerces the digit-only positions of an MRZ line to digits, fixing the OCR-B
    /// misreads that otherwise fail the check digits (e.g. `O`→`0`, `I`→`1`).
    /// Alphanumeric fields (name, nationality, sex) are left untouched.
    private static func coerceDigits(_ line: String, width: Int, positions: [Int]) -> String {
        guard line.count == width else { return line }
        var chars = Array(line)
        for position in positions where position < chars.count {
            chars[position] = letterToDigit(chars[position])
        }
        return String(chars)
    }

    /// TD3 line 2 numeric fields (ICAO 9303 Part 4): doc check, DOB(+check),
    /// expiry(+check), optional check, composite check.
    static func correctTD3DataLine(_ line: String) -> String {
        coerceDigits(line, width: 44, positions: [9] + Array(13...19) + Array(21...27) + [42, 43])
    }

    /// TD2 line 2 numeric fields: doc check[9], DOB[13...19], expiry[21...27],
    /// composite[35]. Nationality[10...12] and sex[20] are left alone.
    static func correctTD2DataLine(_ line: String) -> String {
        coerceDigits(line, width: 36, positions: [9] + Array(13...19) + Array(21...27) + [35])
    }

    /// TD1 line 2 numeric fields: DOB[0...6], expiry[8...14], composite[29].
    /// Nationality[15...17] and sex[7] are left alone.
    static func correctTD1DataLine(_ line: String) -> String {
        coerceDigits(line, width: 30, positions: Array(0...6) + Array(8...14) + [29])
    }

    /// Maps a letter commonly confused for a digit in OCR-B to that digit.
    private static func letterToDigit(_ character: Character) -> Character {
        switch character {
        case "O", "Q", "D": "0"
        case "I", "L": "1"
        case "Z": "2"
        case "A": "4"
        case "S": "5"
        case "G": "6"
        case "T": "7"
        case "B", "R": "8"
        default: character
        }
    }

    private func deliverError(_ error: VIDError) {
        Logger.mrz.vidError("Scanner error: \(error.localizedDescription)")
        DispatchQueue.main.async { [onError] in
            MainActor.assumeIsolated { onError?(error) }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VIDMRZScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        recognize(in: pixelBuffer)
    }
}
