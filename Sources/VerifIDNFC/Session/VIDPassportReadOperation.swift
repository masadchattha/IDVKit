//
//  VIDPassportReadOperation.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation
import OSLog
import VerifIDCore
import VerifIDJPEG2000
import VerifIDMRZ

/// Drives the passport read once BAC has established a Secure Messaging channel:
/// selects each elementary file and reads it in ≤223-byte chunks (staying well
/// inside CoreNFC's ~20 s per-connection budget), then parses COM/DG1/DG2.
///
/// A `Transceiver` abstracts the wire so the whole read is unit-testable with a
/// scripted chip; the CoreNFC path injects ``VIDNFCSession/transceive(_:)``.
struct VIDPassportReadOperation {

    typealias Transceiver = (VIDCommandAPDU) async throws -> VIDResponseAPDU

    let configuration: VIDNFCConfiguration
    let mrzKey: VIDMRZKey

    /// Reads and parses the passport over an already-open transport.
    /// - Parameters:
    ///   - transceive: sends a plain command APDU, returns the raw response.
    ///   - onProgress: called with a data-group label and 0…1 progress.
    func run(
        transceive: @escaping Transceiver,
        onProgress: (String, Double) -> Void = { _, _ in }
    ) async throws -> VIDPassportData {

        // 1. Open the secure channel: PACE when available, else BAC.
        var sm = try await establishSecureChannel(transceive: transceive)

        // Every subsequent command is protected and every response verified.
        let secure: Transceiver = { command in
            let protected = try await sm.protect(command)
            let response = try await transceive(protected)
            return try sm.unprotect(response)
        }

        // Retain the raw bytes of every data group read; passive authentication
        // hashes them against the SOD.
        var rawGroups: [VIDDataGroupID: [UInt8]] = [:]

        // 2. Read COM to learn which data groups are present.
        onProgress("document", 0.1)
        let comBytes = try await readFile(VIDDataGroupParser.File.com, using: secure)
        rawGroups[.com] = comBytes
        let present = (try? VIDDataGroupParser.parseCOMTagList(comBytes)) ?? []
        Logger.nfc.vidDebug("EF.COM read: chip lists \(present.map(\.rawValue).joined(separator: ", "))")

        // 2b. Chip Authentication (anti-clone): read DG14 and, if it advertises
        // Chip Authentication, run it now so it upgrades the secure channel that
        // protects every subsequent read.
        var chipAuthentication: VIDChipAuthenticityResult.CheckStatus = .notSupportedByChip
        if present.contains(.dg14) {
            let dg14 = try await readFile(VIDDataGroupParser.File.dg14, using: secure)
            rawGroups[.dg14] = dg14
            if let params = VIDChipAuthenticationParameters.parse(dg14: dg14) {
                do {
                    sm = try await VIDChipAuthenticationHandler(parameters: params).run(secureTransceive: secure)
                    chipAuthentication = .passed
                } catch {
                    chipAuthentication = .failed(reason: "chip authentication failed: \(error.localizedDescription)")
                }
            }
        }

        // 3. Read DG1 (MRZ) — always present.
        onProgress("details", 0.3)
        let dg1Bytes = try await readFile(VIDDataGroupParser.File.dg1, using: secure)
        rawGroups[.dg1] = dg1Bytes
        let mrz = try VIDDataGroupParser.parseDG1(dg1Bytes)
        Logger.nfc.vidDebug("DG1 read: \(dg1Bytes.count) bytes, document \(mrz.documentNumber)")

        // 4. Read DG2 (face) when requested and present.
        var faceImageData: Data?
        var groupsRead: [VIDDataGroupID] = [.com, .dg1]
        if configuration.readDataGroups.contains(.dg2), present.contains(.dg2) {
            onProgress("photo", 0.5)
            let dg2Bytes = try await readFile(VIDDataGroupParser.File.dg2, using: secure) { fraction in
                onProgress("photo", 0.5 + fraction * 0.4)
            }
            rawGroups[.dg2] = dg2Bytes
            faceImageData = try? decodeFace(dg2Bytes)
            groupsRead.append(.dg2)
            Logger.nfc.vidDebug("DG2 read: \(dg2Bytes.count) bytes, face \(faceImageData != nil ? "decoded" : "decode failed")")
        }

        // 5. Read DG15 (Active Authentication public key) when present.
        var activeAuthKey: VIDActiveAuthentication?
        if present.contains(.dg15) {
            let dg15 = try await readFile(VIDDataGroupParser.File.dg15, using: secure)
            rawGroups[.dg15] = dg15
            // DG14's ActiveAuthenticationInfo pins the ECDSA hash, if present.
            let aaSignatureOID = rawGroups[.dg14].flatMap(VIDChipAuthenticationParameters.activeAuthenticationSignatureOID(dg14:))
            activeAuthKey = VIDActiveAuthentication.parse(dg15: dg15, activeAuthSignatureOID: aaSignatureOID)
        }

        // 6. Read EF.SOD for passive authentication.
        onProgress("verifying", 0.95)
        let sodBytes = try await readFile(VIDDataGroupParser.File.sod, using: secure)
        Logger.nfc.vidDebug("EF.SOD read: \(sodBytes.count) bytes")

        onProgress("verifying", 1.0)

        // 7. Passive authentication: verify DG hashes + SOD signature + DSC→CSCA.
        let passive = VIDPassiveAuthenticator(configuration: configuration.passiveAuthentication)
            .verify(sod: sodBytes, dataGroups: rawGroups)
        Logger.nfc.vidDebug("Passive auth: integrity=\(passive.dataIntegrity), trust=\(passive.chainOfTrust)")

        // 8. Active authentication (standalone challenge/response) when available.
        var activeAuthentication: VIDChipAuthenticityResult.CheckStatus = .notSupportedByChip
        if let activeAuthKey {
            do {
                let ok = try await activeAuthKey.run(secureTransceive: secure)
                activeAuthentication = ok ? .passed : .failed(reason: "signature did not verify")
                Logger.nfc.vidDebug("Active authentication: \(ok ? "passed" : "failed")")
            } catch {
                activeAuthentication = .failed(reason: error.localizedDescription)
            }
        }

        if rawGroups[.dg14] != nil { groupsRead.append(.dg14) }
        if rawGroups[.dg15] != nil { groupsRead.append(.dg15) }

        let authenticity = VIDChipAuthenticityResult(
            passiveAuthentication: passive,
            chipAuthentication: chipAuthentication,
            activeAuthentication: activeAuthentication
        )

        return VIDPassportData(
            mrz: mrz, faceImageData: faceImageData,
            dataGroupsRead: groupsRead, authenticity: authenticity
        )
    }

    // MARK: Secure channel

    /// Opens the secure channel per the configured access protocol: PACE when
    /// the chip advertises a supported profile in EF.CardAccess, otherwise BAC.
    private func establishSecureChannel(transceive: @escaping Transceiver) async throws -> VIDSecureMessaging {
        switch configuration.accessProtocol {
        case .bacOnly:
            return try await VIDBACSession(mrzKey: mrzKey).establish(transceive: transceive)

        case .paceOnly:
            return try await runPACE(transceive: transceive)

        case .automatic:
            // Try PACE; on any PACE failure fall back to BAC (widely supported).
            do {
                let pace = try await runPACE(transceive: transceive)
                Logger.nfc.vidDebug("Secure channel established via PACE")
                return pace
            } catch {
                Logger.nfc.vidDebug("PACE unavailable (\(error.localizedDescription)); falling back to BAC")
                let bac = try await VIDBACSession(mrzKey: mrzKey).establish(transceive: transceive)
                Logger.nfc.vidDebug("Secure channel established via BAC")
                return bac
            }
        }
    }

    private func runPACE(transceive: @escaping Transceiver) async throws -> VIDSecureMessaging {
        // EF.CardAccess is world-readable without secure messaging.
        let cardAccess = try await readFile(VIDDataGroupParser.File.cardAccess, using: transceive)
        let info = try VIDPACEInfo.parse(cardAccess: cardAccess)
        Logger.nfc.vidDebug("PACE: \(info.protocolOID), parameterId \(info.parameterId.map(String.init) ?? "—")")
        guard let parameterId = info.parameterId,
              let curve = VIDStandardCurves.curve(parameterId: parameterId) else {
            throw VIDError.accessControlFailed(detail: "unsupported PACE domain parameters")
        }
        return try await VIDPACEHandler(mrzKey: mrzKey, info: info, curve: curve).run(transceive: transceive)
    }

    // MARK: File reading

    /// Selects an elementary file, reads its length header, then reads the rest
    /// in short chunks.
    private func readFile(
        _ fileID: [UInt8],
        using transceive: Transceiver,
        onProgress: (Double) -> Void = { _ in }
    ) async throws -> [UInt8] {
        // SELECT EF (00 A4 02 0C 02 <FID>).
        let select = VIDCommandAPDU(cla: 0x00, ins: 0xA4, p1: 0x02, p2: 0x0C,
                                    data: fileID, expectedResponseLength: 0)
        try (await transceive(select)).checkSuccess()

        // Read the first 4 bytes to discover the object's total length.
        let head = try await readBinary(offset: 0, length: 4, using: transceive)
        let (totalLength, _) = try Self.totalObjectLength(head)

        var data = head
        var offset = head.count
        while offset < totalLength {
            let chunk = min(0xDF, totalLength - offset) // 223 bytes: safe under SM padding
            let bytes = try await readBinary(offset: offset, length: chunk, using: transceive)
            if bytes.isEmpty { break }
            data.append(contentsOf: bytes)
            offset += bytes.count
            onProgress(Double(offset) / Double(totalLength))
        }
        return Array(data.prefix(totalLength))
    }

    /// READ BINARY (00 B0) at a 15-bit offset.
    private func readBinary(offset: Int, length: Int, using transceive: Transceiver) async throws -> [UInt8] {
        let p1 = UInt8((offset >> 8) & 0x7F)
        let p2 = UInt8(offset & 0xFF)
        let command = VIDCommandAPDU(cla: 0x00, ins: 0xB0, p1: p1, p2: p2,
                                     data: [], expectedResponseLength: length)
        let response = try await transceive(command)
        try response.checkSuccess()
        return response.data
    }

    /// Parses a BER-TLV object's total on-wire length from its leading bytes.
    static func totalObjectLength(_ head: [UInt8]) throws -> (total: Int, headerBytes: Int) {
        var index = 0
        guard !head.isEmpty else { throw VIDError.dataGroupReadFailed("empty file header") }

        // Tag (1–2 bytes).
        if head[0] & 0x1F == 0x1F {
            index = 2
        } else {
            index = 1
        }
        guard index < head.count else { throw VIDError.dataGroupReadFailed("truncated file header") }

        let lengthByte = head[index]
        index += 1
        var valueLength = 0
        if lengthByte & 0x80 == 0 {
            valueLength = Int(lengthByte)
        } else {
            let count = Int(lengthByte & 0x7F)
            guard count > 0, count <= 3, index + count <= head.count else {
                throw VIDError.dataGroupReadFailed("unsupported file length form")
            }
            for _ in 0..<count {
                valueLength = (valueLength << 8) | Int(head[index])
                index += 1
            }
        }
        return (index + valueLength, index)
    }

    // MARK: Face decoding

    private func decodeFace(_ dg2Bytes: [UInt8]) throws -> Data {
        let (imageBytes, isJPEG2000) = try VIDDataGroupParser.parseDG2FaceImage(dg2Bytes)
        if isJPEG2000 {
            // Decode JPEG2000 → re-encode as JPEG so callers get a universally
            // usable image (Apple ImageIO cannot read JPEG2000).
            let cgImage = try VIDJPEG2000Decoder.decode(Data(imageBytes))
            return try Self.jpegData(from: cgImage)
        }
        return Data(imageBytes) // already JPEG
    }

    private static func jpegData(from cgImage: CGImage) throws -> Data {
        guard let data = cgImage.vidJPEGData() else {
            throw VIDError.jpeg2000DecodeFailed(detail: "JPEG re-encode failed")
        }
        return data
    }
}

#if canImport(UIKit)
import UIKit
#endif
import CoreGraphics
