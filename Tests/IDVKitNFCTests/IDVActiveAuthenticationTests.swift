//
//  IDVActiveAuthenticationTests.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 04/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import BigInt
import Crypto
import Foundation
import Testing
@testable import IDVKitNFC

struct ISO9796RecoveryTests {
    private let challenge: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
    private let m1: [UInt8] = (0 ..< 40).map { UInt8($0) }

    @Test func recoversSHA1BlockFillingForm() {
        // ISO 9796-2 DS1: [0x6A] ‖ M1 ‖ SHA1(M1‖challenge) ‖ 0xBC
        let hash = Array(Insecure.SHA1.hash(data: m1 + challenge))
        let block: [UInt8] = [0x6A] + m1 + hash + [0xBC]
        #expect(IDVActiveAuthentication.recoverISO9796_2(block: block, challenge: challenge))
    }

    @Test func recoversSHA256WithTwoByteTrailer() {
        // Trailer 0x34 0xCC identifies SHA-256.
        let hash = Array(SHA256.hash(data: m1 + challenge))
        let block: [UInt8] = [0x6A] + m1 + hash + [0x34, 0xCC]
        #expect(IDVActiveAuthentication.recoverISO9796_2(block: block, challenge: challenge))
    }

    @Test func rejectsWrongChallenge() {
        let hash = Array(Insecure.SHA1.hash(data: m1 + challenge))
        let block: [UInt8] = [0x6A] + m1 + hash + [0xBC]
        #expect(!IDVActiveAuthentication.recoverISO9796_2(block: block, challenge: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    @Test func rejectsTamperedHash() {
        var hash = Array(Insecure.SHA1.hash(data: m1 + challenge))
        hash[0] ^= 0x01
        let block: [UInt8] = [0x6A] + m1 + hash + [0xBC]
        #expect(!IDVActiveAuthentication.recoverISO9796_2(block: block, challenge: challenge))
    }

    @Test func rejectsBadTrailer() {
        let hash = Array(Insecure.SHA1.hash(data: m1 + challenge))
        let block: [UInt8] = [0x6A] + m1 + hash + [0x00]
        #expect(!IDVActiveAuthentication.recoverISO9796_2(block: block, challenge: challenge))
    }
}

struct ActiveAuthenticationRSATests {
    // A freshly generated 1024-bit RSA test key (not a real passport key).
    // d is computed from the primes so the round-trip is self-consistent.
    private let n = BigUInt("c0bc8981e2c717e7c729b461a328de7925b70dd3e5d9c830754296d528d089a773406deced4fac36467f79193ba66e936e47268c56acc66af7a4d2c2afa9705d53628bcac26a68e6ba327527e088c663277cdce11340371655d024ee00e51dd476b1b825d72f8e1ef1c80eea156e6d201f64974f5697901079afc4c321cb5403", radix: 16)!
    private let p = BigUInt("ec04b9877745f1cd4e49e95dc63cb95adc6e97264ee77668879af53abee81733a791c56d6e334b84142905cb48b09a47c2ed7f77ba3eda3eeb811cec9741a6ed", radix: 16)!
    private let q = BigUInt("d10dc0da5ebf8fb307b46173f93609e4b3ccd7c4b89ec6a7294e5741796b47fea3ae955dc9804777021b1b09ee5987487a3b98465f243d7dd9de2f65b8d418af", radix: 16)!
    private let e = BigUInt(65537)
    private var d: BigUInt {
        e.inverse((p - 1) * (q - 1))!
    }

    private let challenge: [UInt8] = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]

    /// Builds an ISO 9796-2 signature the way a chip would (block^d mod n) and
    /// confirms the full RSA public-op + recovery verifies it.
    @Test func verifiesGeneratedRSASignature() {
        let k = (n.bitWidth + 7) / 8
        let hashLength = 20
        let m1Length = k - 1 - hashLength - 1
        let m1 = [UInt8](repeating: 0xAB, count: m1Length)
        let hash = Array(Insecure.SHA1.hash(data: m1 + challenge))
        let block: [UInt8] = [0x6A] + m1 + hash + [0xBC]

        // Chip side: signature = block^d mod n.
        let signature = BigUInt(Data(block)).power(d, modulus: n)
        var sigBytes = Array(signature.serialize())
        if sigBytes.count < k {
            sigBytes = Array(repeating: 0, count: k - sigBytes.count) + sigBytes
        }

        let aa = IDVActiveAuthentication(publicKey: .rsa(modulus: n, exponent: e))
        #expect(aa.verify(signature: sigBytes, challenge: challenge))
        // A different challenge must fail.
        #expect(!aa.verify(signature: sigBytes, challenge: [0, 0, 0, 0, 0, 0, 0, 0]))
    }
}

struct ECDSADERVerificationTests {
    /// Signs a message with a brainpoolP256r1 key and verifies it through the
    /// DER path — the same path used for an EC (brainpool) Document Signer.
    @Test func verifiesBrainpoolECDSADERSignature() throws {
        let curve = IDVStandardCurves.brainpoolP256r1
        let d = try #require(BigUInt("0102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F20", radix: 16))
        let publicKey = curve.multiply(d, curve.generator)
        let message: [UInt8] = Array("idvkit brainpool sod test".utf8)

        let e = BigUInt(Data(SHA256.hash(data: message)))
        let k = try #require(BigUInt("00FEDCBA98765432100123456789ABCDEF00112233445566778899AABBCCDDEEFF", radix: 16))
        let pointR = curve.multiply(k, curve.generator)
        let r = pointR.x % curve.order
        let kInv = try #require(k.inverse(curve.order))
        let s = (kInv * (e + r * d)) % curve.order

        let signature = derSequence([derInteger(r), derInteger(s)])
        #expect(IDVActiveAuthentication.verifyECDSADER(signature: signature, message: message, hash: .sha256, curve: curve, publicKey: publicKey))
        // A tampered message must fail.
        #expect(!IDVActiveAuthentication.verifyECDSADER(signature: signature, message: message + [0x00], hash: .sha256, curve: curve, publicKey: publicKey))
    }

    private func derInteger(_ value: BigUInt) -> [UInt8] {
        var bytes = Array(value.serialize())
        if bytes.isEmpty {
            bytes = [0x00]
        }
        if bytes[0] & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        } // keep it positive
        return [0x02, UInt8(bytes.count)] + bytes
    }

    private func derSequence(_ elements: [[UInt8]]) -> [UInt8] {
        let body = elements.flatMap(\.self)
        return [0x30, UInt8(body.count)] + body
    }
}
