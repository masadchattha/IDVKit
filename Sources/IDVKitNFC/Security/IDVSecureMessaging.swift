//
//  IDVSecureMessaging.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore

/// eMRTD Secure Messaging (ICAO Doc 9303 Part 11 §9.8).
///
/// Every command/response APDU is protected: command data is encrypted (DO'87'),
/// the expected length is carried in DO'97', and a MAC over the padded header +
/// DOs goes in DO'8E'. The Send Sequence Counter (SSC) increments before each
/// command and again before checking each response, binding the exchange against
/// replay.
///
/// Two cryptographic modes share this identical framing:
/// - ``Mode/tripleDES`` — BAC: 8-byte SSC, zero-IV 3DES-CBC, ISO 9797-1 retail MAC.
/// - ``Mode/aes`` — PACE: 16-byte SSC (starts at zero), AES-CBC with a per-message
///   IV = E(KS_Enc, SSC), AES-CMAC truncated to 8 bytes.
struct IDVSecureMessaging {
    enum Mode {
        case tripleDES
        case aes
        var blockSize: Int {
            self == .aes ? 16 : 8
        }
    }

    let mode: Mode
    let ksEnc: [UInt8]
    let ksMac: [UInt8]
    private(set) var ssc: [UInt8]

    /// BAC (3DES) session with an 8-byte initial SSC.
    init(ksEnc: [UInt8], ksMac: [UInt8], initialSSC: [UInt8]) {
        mode = .tripleDES
        self.ksEnc = ksEnc
        self.ksMac = ksMac
        ssc = initialSSC
    }

    /// PACE (AES) session; the SSC starts at zero (16 bytes).
    init(aesKsEnc: [UInt8], ksMac: [UInt8]) {
        mode = .aes
        ksEnc = aesKsEnc
        self.ksMac = ksMac
        ssc = [UInt8](repeating: 0, count: 16)
    }

    /// Increments the SSC as a big-endian integer (with wraparound).
    mutating func incrementSSC() {
        var index = ssc.count - 1
        while index >= 0 {
            ssc[index] = ssc[index] &+ 1
            if ssc[index] != 0 {
                break
            } // no carry
            index -= 1
        }
    }

    /// Wraps a plain command APDU into its protected form (SSC incremented first).
    mutating func protect(_ command: IDVCommandAPDU) throws -> IDVCommandAPDU {
        incrementSSC()

        let maskedHeader: [UInt8] = [command.cla | 0x0C, command.ins, command.p1, command.p2]
        let paddedHeader = pad(maskedHeader)

        var dataObjects: [UInt8] = []

        // DO'87': encrypted command data, prefixed by 0x01 (padding-content indicator).
        if !command.data.isEmpty {
            let encrypted = try encrypt(pad(command.data))
            dataObjects += buildDO(tag: 0x87, value: [0x01] + encrypted)
        }

        // DO'97': expected response length.
        if command.expectedResponseLength > 0 {
            let le: UInt8 = command.expectedResponseLength >= 256 ? 0x00 : UInt8(command.expectedResponseLength)
            dataObjects += buildDO(tag: 0x97, value: [le])
        }

        // DO'8E': MAC over SSC ‖ paddedHeader ‖ dataObjects (then padded).
        let mac = try authenticate(pad(ssc + paddedHeader + dataObjects))
        dataObjects += buildDO(tag: 0x8E, value: mac)

        return IDVCommandAPDU(
            cla: command.cla | 0x0C, ins: command.ins, p1: command.p1, p2: command.p2,
            data: dataObjects, expectedResponseLength: 256
        )
    }

    /// Verifies and decrypts a protected response APDU (SSC incremented first).
    mutating func unprotect(_ response: IDVResponseAPDU) throws -> IDVResponseAPDU {
        incrementSSC()

        let objects = try IDVBERTLV.parseAll(response.data)

        guard let do8E = objects.first(where: { $0.tagNumber == 0x8E }) else {
            throw IDVError.accessControlFailed(detail: "response missing MAC (DO 8E)")
        }
        let maccedObjects = objects.filter { $0.tagNumber != 0x8E }
        let expectedMAC = try authenticate(pad(ssc + maccedObjects.flatMap { serialize($0) }))
        guard do8E.value == expectedMAC else {
            throw IDVError.accessControlFailed(detail: "response MAC mismatch")
        }

        // DO'99': protected status word.
        var sw1 = response.sw1, sw2 = response.sw2
        if let do99 = objects.first(where: { $0.tagNumber == 0x99 }), do99.value.count == 2 {
            sw1 = do99.value[0]
            sw2 = do99.value[1]
        }

        // DO'87': encrypted response data (skip the leading 0x01 indicator).
        var plaintext: [UInt8] = []
        if let do87 = objects.first(where: { $0.tagNumber == 0x87 }), do87.value.count > 1 {
            let decrypted = try decrypt(Array(do87.value.dropFirst()))
            plaintext = IDVPadding.unpad(decrypted)
        }

        return IDVResponseAPDU(data: plaintext, sw1: sw1, sw2: sw2)
    }

    // MARK: Mode-specific crypto

    private func pad(_ data: [UInt8]) -> [UInt8] {
        IDVPadding.pad(data, blockSize: mode.blockSize)
    }

    private func encrypt(_ padded: [UInt8]) throws -> [UInt8] {
        switch mode {
        case .tripleDES:
            return try IDVDESCrypto.tripleDESEncrypt(data: padded, key: ksEnc)
        case .aes:
            let iv = try IDVAESCrypto.encryptBlock(ssc, key: ksEnc) // IV = E(KS_Enc, SSC)
            return try IDVAESCrypto.cbcEncrypt(data: padded, key: ksEnc, iv: iv)
        }
    }

    private func decrypt(_ ciphertext: [UInt8]) throws -> [UInt8] {
        switch mode {
        case .tripleDES:
            return try IDVDESCrypto.tripleDESDecrypt(data: ciphertext, key: ksEnc)
        case .aes:
            let iv = try IDVAESCrypto.encryptBlock(ssc, key: ksEnc)
            return try IDVAESCrypto.cbcDecrypt(data: ciphertext, key: ksEnc, iv: iv)
        }
    }

    private func authenticate(_ padded: [UInt8]) throws -> [UInt8] {
        switch mode {
        case .tripleDES: try IDVRetailMAC.mac(data: padded, key: ksMac)
        case .aes: try IDVAESCrypto.cmac(data: padded, key: ksMac, outputLength: 8)
        }
    }

    // MARK: DO helpers

    private func buildDO(tag: UInt8, value: [UInt8]) -> [UInt8] {
        [tag] + encodeLength(value.count) + value
    }

    private func serialize(_ tlv: IDVBERTLV) -> [UInt8] {
        tlv.tag + encodeLength(tlv.value.count) + tlv.value
    }

    private func encodeLength(_ length: Int) -> [UInt8] {
        if length < 0x80 {
            return [UInt8(length)]
        }
        if length <= 0xFF {
            return [0x81, UInt8(length)]
        }
        return [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
    }
}
