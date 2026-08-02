//
//  IDVFaceMatcher.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Accelerate
import CoreGraphics
import CoreImage
import CoreML
import Foundation
import IDVKitCore
import ImageIO
import OSLog
import UniformTypeIdentifiers
import Vision

/// On-device face matching: Vision landmarks → ArcFace 5-point alignment
/// (112×112) → face-embedding CoreML model → cosine similarity.
///
/// Guarantees:
///  - The CoreML model loads from the SDK's own bundle (`Bundle.module`).
///  - The result always includes the similarity score — never a bare `Bool`.
///  - Nothing is uploaded anywhere; embeddings never leave the process.
///
/// The bundled model is expected to take a `[1, 3, 112, 112]` NCHW Float32 input
/// and output a face embedding vector. The model-specific spec (feature names,
/// input size, pixel normalization) lives in ``ModelSpec`` — update it to match
/// whichever licensed model is bundled in `Resources`.
public final class IDVFaceMatcher {
    /// Matching options — notably ``IDVFaceConfiguration/matchThreshold``.
    public let configuration: IDVFaceConfiguration

    /// Creates a face matcher.
    /// - Parameter configuration: Matching options; the default uses a cosine
    ///   similarity threshold of `0.65`.
    public init(configuration: IDVFaceConfiguration = .init()) {
        self.configuration = configuration
    }

    /// Compares a document (reference) face against a live selfie. Both images
    /// must already be upright (correct pixel orientation).
    ///
    /// Returns the similarity and the match decision — it does **not** throw when
    /// the score is below threshold (the caller decides what a non-match means).
    /// It throws only when a face can't be found or the model can't run.
    ///
    /// - Throws: ``IDVError/noFaceDetected(inImage:)``,
    ///   ``IDVError/modelLoadFailed(detail:)``.
    public func match(reference: CGImage, live: CGImage) throws -> IDVFaceMatchResult {
        let referenceEmbedding = try Self.generateEmbedding(from: reference, label: "document", enforceSingleFace: false)
        // The live selfie must contain exactly one face — reject a frame with a
        // second person in view.
        let liveEmbedding = try Self.generateEmbedding(from: live, label: "selfie", enforceSingleFace: true)
        let similarity = Self.cosineSimilarity(referenceEmbedding, liveEmbedding)
        let isMatch = similarity > configuration.matchThreshold
        Logger.face.idvDebug("Face match: similarity=\(similarity) threshold=\(configuration.matchThreshold) → \(isMatch ? "match" : "no match")")
        return IDVFaceMatchResult(
            isMatch: isMatch,
            similarity: similarity,
            thresholdUsed: configuration.matchThreshold,
            referenceImageData: reference.idvJPEGData() ?? Data(),
            liveImageData: live.idvJPEGData() ?? Data()
        )
    }

    // MARK: - Model spec (must match the bundled CoreML model)

    /// Configuration of the bundled embedding model. **Update to match whichever
    /// licensed model ships in `Resources`.** The defaults follow the common
    /// ArcFace/MobileFaceNet convention (112×112, ImageNet normalization).
    enum ModelSpec {
        /// Resource name of the compiled model (`<name>.mlmodelc`) in `Bundle.module`.
        static let resourceName = "IDVFaceEmbedding"
        static let inputFeature = "input_image"
        static let outputFeature = "embedding"
        static let inputSize = 112
        /// Per-channel mean/std applied after scaling pixels to [0, 1].
        static let mean: [Float] = [0.485, 0.456, 0.406]
        static let std: [Float] = [0.229, 0.224, 0.225]
    }

    /// ArcFace 112×112 reference eye positions (origin top-left). Left-in-image is
    /// the subject's right eye; right-in-image is the subject's left eye.
    private static let arcFaceRefLeftInImage = CGPoint(x: 38.2946, y: 51.6963)
    private static let arcFaceRefRightInImage = CGPoint(x: 73.5318, y: 51.5014)

    // CIContext is documented as safe to use from multiple threads for rendering,
    // so one cached, immutable instance is fine under strict concurrency.
    private nonisolated(unsafe) static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Model loading (cached, thread-safe)

    private static let modelLock = NSLock()
    /// Guarded by `modelLock`; the unsafe annotation is what lets us hand-lock it.
    private nonisolated(unsafe) static var cachedModel: MLModel?

    private static func loadModel() throws -> MLModel {
        modelLock.lock()
        defer { modelLock.unlock() }
        if let cached = cachedModel {
            return cached
        }
        guard let url = Bundle.module.url(forResource: ModelSpec.resourceName, withExtension: "mlmodelc") else {
            throw IDVError.modelLoadFailed(detail: "\(ModelSpec.resourceName).mlmodelc not found in the IDVKitFace bundle. A licensed face-embedding model must be added to Sources/IDVKitFace/Resources.")
        }
        let model = try MLModel(contentsOf: url)
        cachedModel = model
        return model
    }

    // MARK: - Embedding pipeline

    /// Detect the face's landmarks → align to the ArcFace template → normalize →
    /// run the model → L2-normalize the embedding.
    static func generateEmbedding(from cgImage: CGImage, label: String, enforceSingleFace: Bool) throws -> [Float] {
        let observation = try detectFaceWithLandmarks(in: cgImage, label: label, enforceSingleFace: enforceSingleFace)
        let aligned = try alignFace(from: cgImage, observation: observation)
        let input = try imageToMLMultiArray(aligned)
        let embedding = try runModel(with: input)
        return l2Normalize(embedding)
    }

    /// Vision's request handler runs synchronously on-device, so no continuation
    /// is needed (and returning the non-Sendable observation across one trips
    /// strict concurrency). The observation stays on this thread.
    ///
    /// When `enforceSingleFace` is set, more than one detected face is a hard
    /// error (a second person must not be in the live frame). Otherwise the
    /// largest face is used.
    private static func detectFaceWithLandmarks(in cgImage: CGImage, label: String, enforceSingleFace: Bool) throws -> VNFaceObservation {
        let request = VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let faces = request.results ?? []
        guard !faces.isEmpty else { throw IDVError.noFaceDetected(inImage: label) }
        if enforceSingleFace, faces.count > 1 {
            throw IDVError.multipleFacesDetected(inImage: label)
        }
        // Use the most prominent face (largest bounding box).
        return faces.max {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        } ?? faces[0]
    }

    /// Aligns a face to 112×112 via a similarity transform from the detected eye
    /// centers to the ArcFace reference template. Handles mirrored selfies by
    /// choosing the eye correspondence from the dominant axis of separation
    /// (ported verbatim from the validated Votari implementation — sub-pixel noise
    /// on the minor axis can otherwise flip the rotation sign).
    private static func alignFace(from cgImage: CGImage, observation: VNFaceObservation) throws -> CGImage {
        let W = CGFloat(cgImage.width)
        let H = CGFloat(cgImage.height)
        let bb = observation.boundingBox

        guard let landmarks = observation.landmarks,
              let leftEyeRegion = landmarks.leftEye, leftEyeRegion.pointCount > 0,
              let rightEyeRegion = landmarks.rightEye, rightEyeRegion.pointCount > 0 else {
            return try cropFaceFallback(from: cgImage, faceRect: bb)
        }

        func center(of region: VNFaceLandmarkRegion2D) -> CGPoint {
            let pts = region.normalizedPoints
            let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
            let cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
            return CGPoint(x: cx, y: cy)
        }

        let leCenter = center(of: leftEyeRegion)
        let reCenter = center(of: rightEyeRegion)

        // Landmark points are relative to the face bounding box; lift to absolute
        // CIImage coordinates (origin bottom-left, matching Vision).
        let subjectLeftEye = CGPoint(
            x: (bb.origin.x + leCenter.x * bb.width) * W,
            y: (bb.origin.y + leCenter.y * bb.height) * H
        )
        let subjectRightEye = CGPoint(
            x: (bb.origin.x + reCenter.x * bb.width) * W,
            y: (bb.origin.y + reCenter.y * bb.height) * H
        )

        // Order the eyes by the dominant axis of separation: horizontal for an
        // upright image, vertical for a rotated one. Sorting by the minor axis is
        // unreliable — sub-pixel noise flips the rotation ±90°.
        let srcL: CGPoint
        let srcR: CGPoint
        let eyeDx = abs(subjectLeftEye.x - subjectRightEye.x)
        let eyeDy = abs(subjectLeftEye.y - subjectRightEye.y)
        if eyeDx >= eyeDy {
            if subjectLeftEye.x <= subjectRightEye.x {
                srcL = subjectLeftEye; srcR = subjectRightEye
            } else {
                srcL = subjectRightEye; srcR = subjectLeftEye
            }
        } else {
            if subjectLeftEye.y >= subjectRightEye.y {
                srcL = subjectLeftEye; srcR = subjectRightEye
            } else {
                srcL = subjectRightEye; srcR = subjectLeftEye
            }
        }

        // Reference positions in CIImage coords (bottom-left): flip Y from the
        // top-left template.
        let size = CGFloat(ModelSpec.inputSize)
        let dstL = CGPoint(x: arcFaceRefLeftInImage.x, y: size - arcFaceRefLeftInImage.y)
        let dstR = CGPoint(x: arcFaceRefRightInImage.x, y: size - arcFaceRefRightInImage.y)

        // Similarity transform: dst = [a, -b; b, a] · src + [tx, ty].
        let sdx = srcR.x - srcL.x
        let sdy = srcR.y - srcL.y
        let ddx = dstR.x - dstL.x
        let ddy = dstR.y - dstL.y
        let det = sdx * sdx + sdy * sdy
        guard det > 0 else { return try cropFaceFallback(from: cgImage, faceRect: bb) }

        let a = (ddx * sdx + ddy * sdy) / det
        let b = (ddy * sdx - ddx * sdy) / det
        let tx = dstL.x - a * srcL.x + b * srcL.y
        let ty = dstL.y - b * srcL.x - a * srcL.y

        let ciImage = CIImage(cgImage: cgImage)
        let transform = CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
        let cropRect = CGRect(x: 0, y: 0, width: ModelSpec.inputSize, height: ModelSpec.inputSize)
        let transformed = ciImage.transformed(by: transform).cropped(to: cropRect)
        guard let output = ciContext.createCGImage(transformed, from: cropRect) else {
            throw IDVError.modelLoadFailed(detail: "face alignment render failed")
        }
        return output
    }

    /// Fallback when eye landmarks are missing: a padded bounding-box crop.
    private static func cropFaceFallback(from cgImage: CGImage, faceRect: CGRect) throws -> CGImage {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let x = faceRect.origin.x * imageWidth
        let y = (1.0 - faceRect.origin.y - faceRect.height) * imageHeight
        let width = faceRect.width * imageWidth
        let height = faceRect.height * imageHeight
        let padding: CGFloat = 0.3
        let paddedX = max(0, x - width * padding)
        let paddedY = max(0, y - height * padding)
        let paddedWidth = min(imageWidth - paddedX, width * (1 + 2 * padding))
        let paddedHeight = min(imageHeight - paddedY, height * (1 + 2 * padding))
        let cropRect = CGRect(x: paddedX, y: paddedY, width: paddedWidth, height: paddedHeight)
        guard let cropped = cgImage.cropping(to: cropRect) else {
            throw IDVError.modelLoadFailed(detail: "face crop failed")
        }
        return cropped
    }

    // MARK: - Image → MLMultiArray

    /// Resizes to 112×112 and packs into `[1, 3, 112, 112]` NCHW with the model's
    /// pixel normalization (ToTensor → per-channel mean/std).
    private static func imageToMLMultiArray(_ cgImage: CGImage) throws -> MLMultiArray {
        let size = ModelSpec.inputSize
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw IDVError.modelLoadFailed(detail: "could not create image context")
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let pixelData = context.data else {
            throw IDVError.modelLoadFailed(detail: "could not read image pixels")
        }
        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: size * size * 4)

        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)], dataType: .float32)
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(array.dataPointer))
        let channelStride = size * size
        let mean = ModelSpec.mean, std = ModelSpec.std
        for y in 0 ..< size {
            for x in 0 ..< size {
                let pixelIndex = (y * size + x) * 4
                let r = Float(pixels[pixelIndex]) / 255.0
                let g = Float(pixels[pixelIndex + 1]) / 255.0
                let b = Float(pixels[pixelIndex + 2]) / 255.0
                let spatialIndex = y * size + x
                ptr[0 * channelStride + spatialIndex] = (r - mean[0]) / std[0]
                ptr[1 * channelStride + spatialIndex] = (g - mean[1]) / std[1]
                ptr[2 * channelStride + spatialIndex] = (b - mean[2]) / std[2]
            }
        }
        return array
    }

    // MARK: - Inference

    private static func runModel(with input: MLMultiArray) throws -> [Float] {
        let model = try loadModel()
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            ModelSpec.inputFeature: MLFeatureValue(multiArray: input)
        ])
        let prediction = try model.prediction(from: provider)
        guard let value = prediction.featureValue(for: ModelSpec.outputFeature),
              let multiArray = value.multiArrayValue else {
            throw IDVError.modelLoadFailed(detail: "model produced no '\(ModelSpec.outputFeature)' output")
        }
        return extractFloats(from: multiArray)
    }

    /// Extracts `[Float]` from an MLMultiArray, handling Float16 (ANE/GPU) output.
    private static func extractFloats(from multiArray: MLMultiArray) -> [Float] {
        let length = multiArray.count
        var result = [Float](repeating: 0, count: length)
        if multiArray.dataType == .float16 {
            let ptr = multiArray.dataPointer.bindMemory(to: Float16.self, capacity: length)
            for i in 0 ..< length {
                result[i] = Float(ptr[i])
            }
        } else {
            let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: length)
            for i in 0 ..< length {
                result[i] = ptr[i]
            }
        }
        return result
    }

    // MARK: - Math

    /// Cosine similarity of two embeddings, in −1…1.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    /// Scales a vector to unit L2 length.
    static func l2Normalize(_ vector: [Float]) -> [Float] {
        var squaredSum: Float = 0
        vDSP_dotpr(vector, 1, vector, 1, &squaredSum, vDSP_Length(vector.count))
        let norm = sqrt(squaredSum)
        guard norm > 0 else { return vector }
        var result = [Float](repeating: 0, count: vector.count)
        var normValue = norm
        vDSP_vsdiv(vector, 1, &normValue, &result, 1, vDSP_Length(vector.count))
        return result
    }

    // MARK: - Encoding
}
