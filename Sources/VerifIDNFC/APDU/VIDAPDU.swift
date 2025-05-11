//
//  VIDAPDU.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation
import VerifIDCore

/// An ISO 7816-4 command APDU (header + optional command data + expected length).
///
/// Kept transport-agnostic: ``VIDNFCSession`` converts these to `NFCISO7816APDU`
/// for CoreNFC, which lets the command layer and secure-messaging layer be unit
/// tested without any NFC hardware.
struct VIDCommandAPDU: Equatable {
    var cla: UInt8
    var ins: UInt8
    var p1: UInt8
    var p2: UInt8
    /// Command data field (Lc is derived from its length).
    var data: [UInt8]
    /// Expected response length. `256` encodes the common "Le = 0x00" (up to 256).
    var expectedResponseLength: Int

    init(cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8, data: [UInt8] = [], expectedResponseLength: Int = 256) {
        self.cla = cla
        self.ins = ins
        self.p1 = p1
        self.p2 = p2
        self.data = data
        self.expectedResponseLength = expectedResponseLength
    }

    /// The four header bytes (CLA INS P1 P2) — the input the retail MAC covers
    /// (after padding) in secure messaging.
    var header: [UInt8] {
        [cla, ins, p1, p2]
    }

    /// Serializes to the short-length wire encoding used by eMRTD reads.
    /// (Extended-length APDUs are not required for passports.)
    var encoded: [UInt8] {
        var bytes = header
        if !data.isEmpty {
            bytes.append(UInt8(data.count)) // Lc
            bytes.append(contentsOf: data)
        }
        if expectedResponseLength > 0 {
            bytes.append(expectedResponseLength >= 256 ? 0x00 : UInt8(expectedResponseLength)) // Le
        }
        return bytes
    }
}

/// An ISO 7816-4 response APDU: data field plus the two status-word bytes.
struct VIDResponseAPDU: Equatable {
    var data: [UInt8]
    var sw1: UInt8
    var sw2: UInt8

    /// The combined status word (e.g. `0x9000` for success).
    var statusWord: UInt16 {
        (UInt16(sw1) << 8) | UInt16(sw2)
    }

    /// `true` when the status word is `0x9000` (normal processing).
    var isSuccess: Bool {
        statusWord == 0x9000
    }

    /// Throws a descriptive ``VIDError`` unless the status word is success.
    func checkSuccess() throws {
        guard isSuccess else {
            throw VIDError.nfcSessionFailed(detail: String(format: "chip returned status 0x%04X", statusWord))
        }
    }
}
