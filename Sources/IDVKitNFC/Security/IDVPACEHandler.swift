//
//  IDVPACEHandler.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import BigInt
import Foundation
import IDVKitCore
import IDVKitMRZ

/// Runs PACE-ECDH-GM (ICAO Doc 9303 Part 11 §4.4) and returns the AES
/// Secure Messaging session it establishes.
///
/// Every cryptographic step here is validated against the Appendix G worked
/// example (see the elliptic-curve, key-derivation, and token tests). The
/// transport is injected so the handshake is unit-testable with a scripted chip.
struct IDVPACEHandler {
    typealias Transceiver = (IDVCommandAPDU) async throws -> IDVResponseAPDU

    let mrzKey: IDVMRZKey
    let info: IDVPACEInfo
    let curve: IDVEllipticCurve

    /// Performs the full PACE handshake over `transceive`.
    /// `randomScalar` is injectable for deterministic testing.
    func run(
        transceive: Transceiver,
        randomScalar: (BigUInt) -> BigUInt = IDVPACEHandler.secureRandomScalar
    ) async throws -> IDVSecureMessaging {
        guard info.isECDH, info.mapping == .generic else {
            throw IDVError.accessControlFailed(detail: "unsupported PACE protocol \(info.protocolOID)")
        }
        guard let cipher = info.cipher, let oidBytes = info.protocolOIDBytes else {
            throw IDVError.accessControlFailed(detail: "unsupported PACE cipher")
        }
        let kPi = try IDVPACEKeyDerivation.passwordKey(from: mrzKey, cipher: cipher)

        // Step 1: MSE:Set AT — select the mechanism + MRZ password.
        try await mseSetAT(oidBytes: oidBytes, transceive: transceive)

        // Step 2: GET NONCE → encrypted nonce z; decrypt to s.
        let z = try await generalAuthenticate(step: 0x7C, inner: nil, chaining: true,
                                              expectTag: 0x80, transceive: transceive)
        let s = try decryptNonce(z, key: kPi, cipher: cipher)

        // Step 3: Map nonce (Generic Mapping): send t·G, receive chip mapping key.
        let t = randomScalar(curve.order)
        let terminalMapPub = curve.multiply(t, curve.generator)
        let chipMapBytes = try await generalAuthenticate(
            step: 0x7C, inner: (0x81, curve.encodePoint(terminalMapPub)),
            chaining: true, expectTag: 0x82, transceive: transceive
        )
        guard let chipMapPub = curve.decodePoint(chipMapBytes) else {
            throw IDVError.accessControlFailed(detail: "invalid chip mapping key")
        }
        let h = curve.multiply(t, chipMapPub) // anonymous ECDH
        let mappedGenerator = curve.add(curve.multiply(sScalar(s), curve.generator), h) // Ĝ = s·G + H
        guard !mappedGenerator.isInfinity else {
            throw IDVError.accessControlFailed(detail: "degenerate mapped generator")
        }

        // Step 4: Ephemeral key agreement on the mapped generator.
        let d = randomScalar(curve.order)
        let terminalEphPub = curve.multiply(d, mappedGenerator)
        let chipEphBytes = try await generalAuthenticate(
            step: 0x7C, inner: (0x83, curve.encodePoint(terminalEphPub)),
            chaining: true, expectTag: 0x84, transceive: transceive
        )
        guard let chipEphPub = curve.decodePoint(chipEphBytes) else {
            throw IDVError.accessControlFailed(detail: "invalid chip ephemeral key")
        }
        let sharedPoint = curve.multiply(d, chipEphPub)
        let sharedSecret = curve.fieldBytes(sharedPoint.x) // K = x-coordinate

        let ksEnc = IDVPACEKeyDerivation.encryptionKey(sharedSecret: sharedSecret, cipher: cipher)
        let ksMac = IDVPACEKeyDerivation.macKey(sharedSecret: sharedSecret, cipher: cipher)

        // Step 5: Mutual authentication — exchange and verify tokens.
        let terminalToken = try IDVPACEToken.token(
            peerPublicKeyObject: IDVPACEToken.publicKeyObject(
                protocolOID: oidBytes, encodedPoint: curve.encodePoint(chipEphPub)
            ),
            macKey: ksMac
        )
        let chipTokenBytes = try await generalAuthenticate(
            step: 0x7C, inner: (0x85, terminalToken), chaining: false,
            expectTag: 0x86, transceive: transceive
        )
        let expectedChipToken = try IDVPACEToken.token(
            peerPublicKeyObject: IDVPACEToken.publicKeyObject(
                protocolOID: oidBytes, encodedPoint: curve.encodePoint(terminalEphPub)
            ),
            macKey: ksMac
        )
        guard chipTokenBytes == expectedChipToken else {
            throw IDVError.accessControlFailed(detail: "PACE chip token mismatch (wrong MRZ key?)")
        }

        return IDVSecureMessaging(aesKsEnc: ksEnc, ksMac: ksMac)
    }

    // MARK: Steps

    private func mseSetAT(oidBytes: [UInt8], transceive: Transceiver) async throws {
        // 00 22 C1 A4 { 80 <oid> 83 01 01 }   (password ref 01 = MRZ)
        let data = tlv(0x80, oidBytes) + tlv(0x83, [0x01])
        let command = IDVCommandAPDU(cla: 0x00, ins: 0x22, p1: 0xC1, p2: 0xA4,
                                     data: data, expectedResponseLength: 0)
        try await (transceive(command)).checkSuccess()
    }

    /// One General Authenticate (INS 0x86) exchange. `inner` is the DO to send
    /// inside the 0x7C wrapper (nil for the empty GET NONCE); `expectTag` is the
    /// inner DO tag to extract from the response.
    private func generalAuthenticate(
        step: UInt8, inner: (tag: UInt8, value: [UInt8])?, chaining: Bool,
        expectTag: UInt8, transceive: Transceiver
    ) async throws -> [UInt8] {
        let body = inner.map { tlv($0.tag, $0.value) } ?? []
        let command = IDVCommandAPDU(
            cla: chaining ? 0x10 : 0x00, ins: 0x86, p1: 0x00, p2: 0x00,
            data: tlv(step, body), expectedResponseLength: 256
        )
        let response = try await transceive(command)
        try response.checkSuccess()

        let wrapper = try IDVBERTLV.parse(response.data).tlv
        guard wrapper.tagNumber == UInt32(step),
              let inner = wrapper.children.first(where: { $0.tagNumber == UInt32(expectTag) }) else {
            throw IDVError.accessControlFailed(detail: "missing DO \(String(expectTag, radix: 16)) in PACE response")
        }
        return inner.value
    }

    private func decryptNonce(_ z: [UInt8], key: [UInt8], cipher: IDVPACEKeyDerivation.Cipher) throws -> [UInt8] {
        // s = D(K_pi, z), AES-CBC, IV = 0, single block, no padding.
        try IDVAESCrypto.cbcDecrypt(data: z, key: key, iv: [UInt8](repeating: 0, count: 16))
    }

    private func sScalar(_ s: [UInt8]) -> BigUInt {
        BigUInt(Data(s))
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

    /// A uniformly random scalar in `1 ..< order`.
    static func secureRandomScalar(order: BigUInt) -> BigUInt {
        let byteCount = (order.bitWidth + 7) / 8
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        let value = BigUInt(Data(bytes)) % (order - 1)
        return value + 1
    }
}
