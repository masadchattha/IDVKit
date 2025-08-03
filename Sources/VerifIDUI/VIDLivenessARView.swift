//
//  VIDLivenessARView.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 12/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import ARKit
import CoreImage
import SwiftUI
import VerifIDCore
import VerifIDFace

/// SwiftUI bridge over an `ARSCNView` running front-camera face tracking. It
/// converts each `ARFaceAnchor` into a plain ``VIDFaceFrame`` (so the liveness
/// logic stays ARKit-free) and, on request, captures the current frame as an
/// upright `CGImage` for face matching.
///
/// Requires a TrueDepth camera; on unsupported devices `onUnsupported` fires and
/// no session starts.
struct VIDLivenessARView: UIViewControllerRepresentable {
    var onFrame: (VIDFaceFrame) -> Void
    var onFaceLost: () -> Void = {}
    var onCapture: (CGImage) -> Void
    var onLightEstimate: (CGFloat) -> Void = { _ in }
    var onFaceCount: (Int) -> Void = { _ in }
    var onUnsupported: () -> Void = {}

    @Binding var captureRequested: Bool
    @Binding var sessionPaused: Bool

    func makeUIViewController(context: Context) -> VIDLivenessARController {
        let controller = VIDLivenessARController()
        controller.tracker.onFrame = onFrame
        controller.tracker.onFaceLost = onFaceLost
        controller.tracker.onCapture = onCapture
        controller.tracker.onLightEstimate = onLightEstimate
        controller.tracker.onFaceCount = onFaceCount
        controller.onUnsupported = onUnsupported
        return controller
    }

    func updateUIViewController(_ controller: VIDLivenessARController, context: Context) {
        if captureRequested {
            controller.tracker.requestCapture()
            DispatchQueue.main.async { captureRequested = false }
        }
        if sessionPaused {
            controller.pauseSession()
        }
    }
}

/// UIKit controller owning the AR face-tracking session (main-actor UI only —
/// the ARKit delegate callbacks live on ``FaceTracker``, off the main actor).
final class VIDLivenessARController: UIViewController {
    let tracker = FaceTracker()
    var onUnsupported: (() -> Void)?
    private var sceneView: ARSCNView!
    /// A background queue for ARSession callbacks. Without this the delegate runs
    /// on the main thread, which — competing with SwiftUI's per-frame camera
    /// render — saturates and makes ARKit stall/retain frames.
    private let sessionQueue = DispatchQueue(label: "dev.verifid.face.arsession")

    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.session.delegate = tracker
        sceneView.session.delegateQueue = sessionQueue
        sceneView.automaticallyUpdatesLighting = true
        // Mirror horizontally for a natural selfie preview.
        sceneView.layer.transform = CATransform3DMakeScale(-1, 1, 1)
        tracker.sceneView = sceneView
        view.addSubview(sceneView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard ARFaceTrackingConfiguration.isSupported else {
            onUnsupported?()
            return
        }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        // Track up to two faces so we can DETECT (and reject) a second person in
        // frame; only the primary face drives the challenges.
        configuration.maximumNumberOfTrackedFaces = min(
            VIDLayout.FaceTracking.maxTrackedFaces,
            ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
        )
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    func pauseSession() {
        sceneView.session.pause()
    }
}

/// ARKit delegate bridge. ARKit invokes these callbacks on its render thread, so
/// this type is intentionally **not** main-actor isolated; it hops every callback
/// to the main queue and guards its one shared flag with a lock.
final class FaceTracker: NSObject, ARSCNViewDelegate, ARSessionDelegate, @unchecked Sendable {
    // Set once on the main actor before the session starts, then only read.
    var onFrame: ((VIDFaceFrame) -> Void)?
    var onFaceLost: (() -> Void)?
    var onCapture: ((CGImage) -> Void)?
    var onLightEstimate: ((CGFloat) -> Void)?
    var onFaceCount: ((Int) -> Void)?
    weak var sceneView: ARSCNView?

    private let lock = NSLock()
    private var captureRequested = false
    private var lightFrameCount = 0
    private var primaryID: UUID? // the face that drives the challenges
    private let ciContext = CIContext()

    func requestCapture() {
        lock.lock(); captureRequested = true; lock.unlock()
    }

    private func consumeCaptureRequest() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let value = captureRequested
        captureRequested = false
        return value
    }

    /// The primary face to track, kept stable across frames by identifier so a
    /// second face never hijacks the challenge evaluation.
    private func primaryFace(among faces: [ARFaceAnchor]) -> ARFaceAnchor? {
        lock.lock(); defer { lock.unlock() }
        if let id = primaryID, let existing = faces.first(where: { $0.identifier == id }) {
            return existing
        }
        primaryID = faces.first?.identifier
        return faces.first
    }

    // MARK: ARSessionDelegate

    /// Everything runs off the per-frame update so the face COUNT is reported
    /// continuously (not just on add/remove) — otherwise a second face that's
    /// already present when the session resets would go unnoticed.
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lightFrameCount += 1
        if lightFrameCount % VIDLayout.Light.sampleFrameInterval == 0, let light = frame.lightEstimate {
            let onLightEstimate = onLightEstimate
            let intensity = light.ambientIntensity
            DispatchQueue.main.async { onLightEstimate?(intensity) }
        }

        // Only count faces ACTIVELY tracked this frame — ARKit keeps a face's
        // anchor alive (isTracked == false) for a while after it leaves the frame,
        // which would otherwise pin the count at 2 forever.
        let faces = frame.anchors.compactMap { $0 as? ARFaceAnchor }.filter(\.isTracked)
        let count = faces.count
        let primary = primaryFace(among: faces)
        let faceFrame = primary.map { Self.faceFrame(from: $0) }
        let (onFaceCount, onFrame, onFaceLost) = (onFaceCount, onFrame, onFaceLost)
        DispatchQueue.main.async {
            onFaceCount?(count)
            if count == 0 {
                onFaceLost?()
            } else if let faceFrame {
                onFrame?(faceFrame)
            }
        }
        if primary != nil, consumeCaptureRequest() {
            captureFrame(frame)
        }
    }

    // MARK: Frame conversion + capture

    /// Reduces an `ARFaceAnchor` to the plain values liveness needs. Blend-shape
    /// names are ARKit's (the mirror correction lives in ``VIDLivenessSession``).
    private static func faceFrame(from anchor: ARFaceAnchor) -> VIDFaceFrame {
        let shapes = anchor.blendShapes
        func value(_ key: ARFaceAnchor.BlendShapeLocation) -> Float {
            shapes[key]?.floatValue ?? 0
        }
        let t = anchor.transform
        return VIDFaceFrame(
            eyeBlinkLeft: value(.eyeBlinkLeft),
            eyeBlinkRight: value(.eyeBlinkRight),
            smileLeft: value(.mouthSmileLeft),
            smileRight: value(.mouthSmileRight),
            jawOpen: value(.jawOpen),
            yaw: atan2(t.columns.2.x, t.columns.2.z),
            pitch: asin(-t.columns.2.x),
            distance: -t.columns.3.z
        )
    }

    private func captureFrame(_ frame: ARFrame) {
        // Uses the frame handed to the delegate on this queue, so there's no need
        // to reach back into the MainActor-isolated `sceneView.session`.
        // The captured buffer is landscape sensor orientation; rotate to upright
        // portrait so Vision's landmark detection sees a correctly-oriented face.
        // (Orientation is device-verified on hardware.)
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let onCapture = onCapture
        DispatchQueue.main.async { onCapture?(cgImage) }
    }
}
