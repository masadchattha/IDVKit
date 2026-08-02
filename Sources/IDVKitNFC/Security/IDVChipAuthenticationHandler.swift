//
//  IDVChipAuthenticationHandler.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 04/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import BigInt
import Foundation
import IDVKitCore
import OSLog

/// Performs Chip Authentication (ICAO 9303 Part 11 §6.2 / BSI TR-03110): an
/// ephemeral-static ECDH with the chip's DG14 static key. The resulting shared
/// secret derives fresh Secure Messaging keys — a cloned chip can't produce
/// them without the static private key, so it proves the chip is genuine.
///
/// This reuses the exact primitives validated for PACE: elliptic-curve ECDH,
/// the PACE key-derivation, and AES Secure Messaging.
struct IDVChipAuthenticationHandler {
    typealias Transceiver = (IDVCommandAPDU) async throws -> IDVResponseAPDU

    let parameters: IDVChipAuthenticationParameters

    /// Runs Chip Authentication over the current (BAC/PACE) secure channel and
    /// returns a **new** ``IDVSecureMessaging`` to use for all subsequent reads.
    /// `randomScalar` is injectable for testing.
    func run(
        secureTransceive: Transceiver,
        randomScalar: (BigUInt) -> BigUInt = IDVPACEHandler.secureRandomScalar
    ) async throws -> IDVSecureMessaging {
        guard let cipher = parameters.cipher else {
            throw IDVError.accessControlFailed(detail: "unsupported Chip Authentication cipher")
        }
        guard let oidBytes = try? oidDER(parameters.protocolOID) else {
            throw IDVError.accessControlFailed(detail: "invalid CA protocol OID")
        }

        let curve = parameters.curve

        // Terminal ephemeral key pair on the chip's curve.
        let ephemeralPrivate = randomScalar(curve.order)
        let ephemeralPublic = curve.multiply(ephemeralPrivate, curve.generator)

        // MSE:Set AT — select the CA mechanism (DO 80 = OID, DO 84 = keyId?).
        var mseData = tlv(0x80, oidBytes)
        if let keyId = parameters.keyId {
            mseData += tlv(0x84, bigEndianBytes(keyId))
        }
        let mse = IDVCommandAPDU(cla: 0x00, ins: 0x22, p1: 0x41, p2: 0xA4,
                                 data: mseData, expectedResponseLength: 0)
        try await (secureTransceive(mse)).checkSuccess()

        // General Authenticate — send the terminal ephemeral public key (DO 80
        // inside DO 7C).
        let gaBody = tlv(0x7C, tlv(0x80, curve.encodePoint(ephemeralPublic)))
        let ga = IDVCommandAPDU(cla: 0x00, ins: 0x86, p1: 0x00, p2: 0x00,
                                data: gaBody, expectedResponseLength: 256)
        try await (secureTransceive(ga)).checkSuccess()

        // Shared secret K = x-coordinate of (ephemeralPrivate · chipStaticPublic).
        let sharedPoint = curve.multiply(ephemeralPrivate, parameters.chipPublicKey)
        guard !sharedPoint.isInfinity else {
            throw IDVError.accessControlFailed(detail: "degenerate CA shared secret")
        }
        let sharedSecret = curve.fieldBytes(sharedPoint.x)

        let ksEnc = IDVPACEKeyDerivation.encryptionKey(sharedSecret: sharedSecret, cipher: cipher)
        let ksMac = IDVPACEKeyDerivation.macKey(sharedSecret: sharedSecret, cipher: cipher)
        Logger.nfc.idvDebug("Chip Authentication key agreement complete; restarting secure messaging")

        // New AES Secure Messaging session; SSC resets to zero.
        return IDVSecureMessaging(aesKsEnc: ksEnc, ksMac: ksMac)
    }

    // MARK: Helpers

    private func tlv(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        [tag] + length(value.count) + value
    }

    private func length(_ n: Int) -> [UInt8] {
        if n < 0x80 {
            return [UInt8(n)]
        }
        if n <= 0xFF {
            return [0x81, UInt8(n)]
        }
        return [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
    }

    private func bigEndianBytes(_ value: Int) -> [UInt8] {
        value == 0 ? [0] : withUnsafeBytes(of: UInt(value).bigEndian, Array.init).drop { $0 == 0 }.map(\.self)
    }

    /// DER content bytes of an OID (without the outer 0x06 tag/length).
    private func oidDER(_ dotted: String) throws -> [UInt8] {
        let info = IDVPACEInfo(protocolOID: dotted, version: 1, parameterId: nil)
        guard let bytes = info.protocolOIDBytes else {
            throw IDVError.accessControlFailed(detail: "invalid OID")
        }
        return bytes
    }
}
