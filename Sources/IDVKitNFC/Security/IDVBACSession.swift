//
//  IDVBACSession.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore
import IDVKitMRZ

/// Performs the eMRTD Basic Access Control handshake (ICAO Doc 9303 Part 11
/// §9.7) and produces the ``IDVSecureMessaging`` session used for all
/// subsequent reads.
///
/// Sequence:
/// 1. Derive `K_enc`/`K_mac` from the MRZ key.
/// 2. `GET CHALLENGE` → RND.IC (8 bytes from the chip).
/// 3. Build `S = RND.IFD ‖ RND.IC ‖ K.IFD`, encrypt with `K_enc`, MAC with `K_mac`.
/// 4. `EXTERNAL AUTHENTICATE` with `E.IFD ‖ M.IFD` → the chip returns
///    `E.IC ‖ M.IC`; verify the MAC, decrypt, and check RND.IFD echoes back.
/// 5. `K_seed = K.IFD ⊕ K.IC` → session keys; initial SSC = last 4 of RND.IC ‖
///    last 4 of RND.IFD.
///
/// The transport is injected as an async closure so this handshake is unit
/// testable without NFC hardware.
struct IDVBACSession {
    typealias Transceiver = (IDVCommandAPDU) async throws -> IDVResponseAPDU

    let mrzKey: IDVMRZKey

    /// Runs BAC over `transceive` and returns the established secure-messaging
    /// channel. `randomBytes` is injectable for deterministic testing.
    func establish(
        transceive: Transceiver,
        randomBytes: (Int) -> [UInt8] = IDVBACSession.secureRandom
    ) async throws -> IDVSecureMessaging {
        let kSeed = try IDVBACKeyDerivation.keySeed(from: mrzKey)
        let kEnc = IDVBACKeyDerivation.deriveKey(keySeed: kSeed, type: .encryption)
        let kMac = IDVBACKeyDerivation.deriveKey(keySeed: kSeed, type: .mac)

        // Step 2: GET CHALLENGE (00 84 00 00 08).
        let challenge = IDVCommandAPDU(cla: 0x00, ins: 0x84, p1: 0x00, p2: 0x00, expectedResponseLength: 8)
        let rndICResponse = try await transceive(challenge)
        try rndICResponse.checkSuccess()
        guard rndICResponse.data.count == 8 else {
            throw IDVError.accessControlFailed(detail: "GET CHALLENGE returned \(rndICResponse.data.count) bytes")
        }
        let rndIC = rndICResponse.data

        // Step 3: build the authentication token.
        let rndIFD = randomBytes(8)
        let kIFD = randomBytes(16)
        let s = rndIFD + rndIC + kIFD
        let eIFD = try IDVDESCrypto.tripleDESEncrypt(data: s, key: kEnc)
        let mIFD = try IDVRetailMAC.mac(data: IDVPadding.pad(eIFD), key: kMac)

        // Step 4: EXTERNAL AUTHENTICATE (00 82 00 00) with E.IFD ‖ M.IFD, Le=0x28.
        let authCommand = IDVCommandAPDU(
            cla: 0x00, ins: 0x82, p1: 0x00, p2: 0x00,
            data: eIFD + mIFD, expectedResponseLength: 0x28
        )
        let authResponse = try await transceive(authCommand)
        try authResponse.checkSuccess()
        guard authResponse.data.count == 0x28 else {
            throw IDVError.accessControlFailed(detail: "mutual authentication failed")
        }

        // Verify the chip's MAC over E.IC, then decrypt.
        let eIC = Array(authResponse.data[0 ..< 32])
        let mIC = Array(authResponse.data[32 ..< 40])
        let expectedMIC = try IDVRetailMAC.mac(data: IDVPadding.pad(eIC), key: kMac)
        guard mIC == expectedMIC else {
            throw IDVError.accessControlFailed(detail: "chip authentication token MAC mismatch")
        }
        let decrypted = try IDVDESCrypto.tripleDESDecrypt(data: eIC, key: kEnc)
        guard decrypted.count == 32 else {
            throw IDVError.accessControlFailed(detail: "invalid chip authentication token")
        }

        // R = RND.IC ‖ RND.IFD ‖ K.IC — verify our RND.IFD echoes back.
        let echoedRndIFD = Array(decrypted[8 ..< 16])
        guard echoedRndIFD == rndIFD else {
            throw IDVError.accessControlFailed(detail: "wrong MRZ key or cloned chip (RND.IFD mismatch)")
        }
        let kIC = Array(decrypted[16 ..< 32])

        // Step 5: session keys and initial SSC.
        let sessionSeed = zip(kIFD, kIC).map(^)
        let ksEnc = IDVBACKeyDerivation.deriveKey(keySeed: sessionSeed, type: .encryption)
        let ksMac = IDVBACKeyDerivation.deriveKey(keySeed: sessionSeed, type: .mac)
        let initialSSC = Array(rndIC.suffix(4)) + Array(rndIFD.suffix(4))

        return IDVSecureMessaging(ksEnc: ksEnc, ksMac: ksMac, initialSSC: initialSSC)
    }

    /// Cryptographically secure random bytes (default source for production).
    static func secureRandom(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return bytes
    }
}
