//
//  IDVJPEG2000Decoder.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import COpenJPEG
import CoreGraphics
import Foundation
import OSLog
import IDVKitCore

/// JPEG2000 → `CGImage` decoding for eMRTD DG2 face images.
///
/// Apple's ImageIO cannot decode JPEG2000 on iOS, but every passport chip
/// stores its face image that way. This decoder is backed by OpenJPEG 2.5.4
/// compiled from vendored source, so it works on device, simulator and
/// Mac Catalyst alike.
///
/// Every failure throws ``IDVError/jpeg2000DecodeFailed(detail:)`` —
/// a malformed image can never crash the host app.
public enum IDVJPEG2000Decoder {
    /// JPEG2000 stream flavors.
    public enum Codec: Sendable {
        /// Raw codestream (starts with the SOC marker `FF 4F`).
        case j2k
        /// JP2 container format.
        case jp2
    }

    /// Detects the codec from the leading bytes.
    public static func sniffCodec(_ data: Data) -> Codec {
        if data.count >= 2, data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0x4F {
            return .j2k
        }
        return .jp2
    }

    /// Decodes JPEG2000 data (J2K or JP2) into a `CGImage`.
    ///
    /// - Throws: ``IDVError/jpeg2000DecodeFailed(detail:)``.
    public static func decode(_ data: Data) throws -> CGImage {
        guard !data.isEmpty else {
            throw IDVError.jpeg2000DecodeFailed(detail: "empty data")
        }

        let format: OPJ_CODEC_FORMAT = sniffCodec(data) == .j2k ? OPJ_CODEC_J2K : OPJ_CODEC_JP2
        guard let codec = opj_create_decompress(format) else {
            throw IDVError.jpeg2000DecodeFailed(detail: "could not create decompressor")
        }
        defer { opj_destroy_codec(codec) }

        var parameters = opj_dparameters_t()
        opj_set_default_decoder_parameters(&parameters)
        guard opj_setup_decoder(codec, &parameters) == OPJ_TRUE else {
            throw IDVError.jpeg2000DecodeFailed(detail: "decoder setup failed")
        }

        let context = ReadContext(data: data)
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()

        // Capture OpenJPEG's diagnostics so failures carry a real reason.
        opj_set_error_handler(codec, { message, userData in
            guard let userData else { return }
            let context = Unmanaged<ReadContext>.fromOpaque(userData).takeUnretainedValue()
            context.lastErrorMessage = message.map { String(cString: $0) }
        }, contextPointer)

        guard let stream = opj_stream_default_create(OPJ_TRUE) else {
            throw IDVError.jpeg2000DecodeFailed(detail: "could not create stream")
        }
        defer { opj_stream_destroy(stream) }

        opj_stream_set_user_data(stream, contextPointer, nil)
        opj_stream_set_user_data_length(stream, OPJ_UINT64(data.count))
        opj_stream_set_read_function(stream) { buffer, byteCount, userData in
            guard let userData, let buffer else { return OPJ_SIZE_T.max } // (OPJ_SIZE_T)-1 = EOF
            let context = Unmanaged<ReadContext>.fromOpaque(userData).takeUnretainedValue()
            return context.read(into: buffer, count: byteCount)
        }
        opj_stream_set_skip_function(stream) { byteCount, userData in
            guard let userData else { return -1 }
            let context = Unmanaged<ReadContext>.fromOpaque(userData).takeUnretainedValue()
            return context.skip(byteCount)
        }
        opj_stream_set_seek_function(stream) { position, userData in
            guard let userData else { return OPJ_FALSE }
            let context = Unmanaged<ReadContext>.fromOpaque(userData).takeUnretainedValue()
            return context.seek(to: position)
        }

        var imagePointer: UnsafeMutablePointer<opj_image_t>?
        guard opj_read_header(stream, codec, &imagePointer) == OPJ_TRUE, let imagePointer else {
            opj_image_destroy(imagePointer)
            throw IDVError.jpeg2000DecodeFailed(detail: context.lastErrorMessage ?? "invalid JPEG2000 header")
        }
        defer { opj_image_destroy(imagePointer) }

        guard opj_decode(codec, stream, imagePointer) == OPJ_TRUE else {
            throw IDVError.jpeg2000DecodeFailed(detail: context.lastErrorMessage ?? "decoding failed")
        }
        // The image is fully decoded at this point. opj_end_decompress only
        // re-scans for post-codestream boxes and can fail spuriously on files
        // whose jp2c box uses the legal "size 0 = extends to EOF" form, so its
        // result is logged rather than treated as fatal.
        if opj_end_decompress(codec, stream) != OPJ_TRUE {
            Logger.imaging.idvDebug("opj_end_decompress reported: \(context.lastErrorMessage ?? "unknown")")
        }

        Logger.imaging.idvDebug("JPEG2000 decoded: \(imagePointer.pointee.numcomps) component(s)")
        return try makeCGImage(from: imagePointer.pointee)
    }

    // MARK: - opj_image_t → CGImage

    private static func makeCGImage(from image: opj_image_t) throws -> CGImage {
        let componentCount = Int(image.numcomps)
        guard componentCount >= 1, let components = image.comps else {
            throw IDVError.jpeg2000DecodeFailed(detail: "no image components")
        }

        let first = components[0]
        let width = Int(first.w)
        let height = Int(first.h)
        guard width > 0, height > 0 else {
            throw IDVError.jpeg2000DecodeFailed(detail: "invalid dimensions")
        }
        for index in 0 ..< componentCount {
            let comp = components[index]
            guard Int(comp.w) == width, Int(comp.h) == height, comp.dx == first.dx, comp.dy == first.dy else {
                throw IDVError.jpeg2000DecodeFailed(detail: "subsampled components are not supported")
            }
            guard comp.data != nil else {
                throw IDVError.jpeg2000DecodeFailed(detail: "missing component data")
            }
        }

        let isGray = componentCount < 3
        let channelCount = isGray ? 1 : 4
        let pixelCount = width * height
        var pixels = [UInt8](repeating: 0xFF, count: pixelCount * channelCount)

        /// Normalizes any precision/signedness to unsigned 8-bit.
        func sample(_ comp: opj_image_comp_t, _ index: Int) -> UInt8 {
            var value = comp.data[index]
            if comp.sgnd != 0 {
                value += 1 << (Int32(comp.prec) - 1)
            }
            if comp.prec > 8 {
                value >>= (Int32(comp.prec) - 8)
            }
            return UInt8(clamping: value)
        }

        if isGray {
            let gray = components[0]
            for index in 0 ..< pixelCount {
                pixels[index] = sample(gray, index)
            }
        } else {
            let red = components[0], green = components[1], blue = components[2]
            let alpha: opj_image_comp_t? = componentCount >= 4 ? components[3] : nil
            for index in 0 ..< pixelCount {
                let base = index * 4
                pixels[base] = sample(red, index)
                pixels[base + 1] = sample(green, index)
                pixels[base + 2] = sample(blue, index)
                if let alpha {
                    pixels[base + 3] = sample(alpha, index)
                }
            }
        }

        let colorSpace = isGray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = isGray
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 8 * channelCount,
                bytesPerRow: width * channelCount,
                space: colorSpace, bitmapInfo: bitmapInfo,
                provider: provider, decode: nil,
                shouldInterpolate: true, intent: .defaultIntent
            )
        else {
            throw IDVError.jpeg2000DecodeFailed(detail: "CGImage creation failed")
        }
        return cgImage
    }
}

/// Read-cursor over the input data for OpenJPEG's stream callbacks.
private final class ReadContext {
    let data: Data
    var offset = 0
    var lastErrorMessage: String?

    init(data: Data) {
        self.data = data
    }

    func read(into buffer: UnsafeMutableRawPointer, count: OPJ_SIZE_T) -> OPJ_SIZE_T {
        let remaining = data.count - offset
        guard remaining > 0 else { return OPJ_SIZE_T.max } // EOF
        let toCopy = min(Int(count), remaining)
        data.withUnsafeBytes { rawBuffer in
            buffer.copyMemory(
                from: rawBuffer.baseAddress!.advanced(by: offset),
                byteCount: toCopy
            )
        }
        offset += toCopy
        return OPJ_SIZE_T(toCopy)
    }

    func skip(_ count: OPJ_OFF_T) -> OPJ_OFF_T {
        // Clamp to EOF and report the bytes actually skipped — OpenJPEG's
        // stream bookkeeping requires offset never to pass the declared length.
        guard count >= 0 else { return -1 }
        let actual = min(count, OPJ_OFF_T(data.count - offset))
        offset += Int(actual)
        return actual
    }

    func seek(to position: OPJ_OFF_T) -> OPJ_BOOL {
        guard position >= 0, position <= OPJ_OFF_T(data.count) else { return OPJ_FALSE }
        offset = Int(position)
        return OPJ_TRUE
    }
}
