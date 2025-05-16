//
//  VIDEllipticCurve.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import BigInt
import Foundation

/// A point on a short-Weierstrass elliptic curve in affine coordinates.
struct VIDECPoint: Equatable {
    var x: BigUInt
    var y: BigUInt
    var isInfinity: Bool

    static let infinity = VIDECPoint(x: 0, y: 0, isInfinity: true)

    init(x: BigUInt, y: BigUInt, isInfinity: Bool = false) {
        self.x = x
        self.y = y
        self.isInfinity = isInfinity
    }
}

/// A prime-field short-Weierstrass curve `y² = x³ + ax + b (mod p)`.
///
/// PACE (ICAO 9303 Part 11) needs elliptic-curve point arithmetic over
/// brainpool curves, which Apple's crypto stack does not implement. This is a
/// curve-agnostic implementation driven by the domain parameters read from the
/// chip's `EF.CardAccess`, so the same code serves every standardized curve
/// (brainpool P256/P384/P512, NIST P-256/384/521).
///
/// Only the terminal side runs here, and the EC private keys are single-use
/// ephemerals discarded immediately — so variable-time affine arithmetic is an
/// acceptable trade-off for a reader (the only long-lived secret, the MRZ, is
/// used solely in symmetric crypto).
struct VIDEllipticCurve {
    let p: BigUInt          // field prime
    let a: BigUInt
    let b: BigUInt
    let generator: VIDECPoint
    let order: BigUInt      // order n of the generator
    let fieldByteLength: Int

    // MARK: Field arithmetic (mod p)

    private func mod(_ value: BigInt) -> BigUInt {
        let m = BigInt(p)
        let r = value % m
        return BigUInt(r < 0 ? r + m : r)
    }

    private func addMod(_ x: BigUInt, _ y: BigUInt) -> BigUInt { (x + y) % p }
    private func subMod(_ x: BigUInt, _ y: BigUInt) -> BigUInt { mod(BigInt(x) - BigInt(y)) }
    private func mulMod(_ x: BigUInt, _ y: BigUInt) -> BigUInt { (x * y) % p }
    private func inverseMod(_ x: BigUInt) -> BigUInt? { x.inverse(p) }

    // MARK: Point operations

    /// Adds two points on the curve.
    func add(_ pointP: VIDECPoint, _ pointQ: VIDECPoint) -> VIDECPoint {
        if pointP.isInfinity { return pointQ }
        if pointQ.isInfinity { return pointP }

        if pointP.x == pointQ.x {
            // P + (−P) = ∞, else it's a doubling.
            if addMod(pointP.y, pointQ.y) == 0 { return .infinity }
            return double(pointP)
        }

        // λ = (yQ − yP) / (xQ − xP)
        guard let inv = inverseMod(subMod(pointQ.x, pointP.x)) else { return .infinity }
        let lambda = mulMod(subMod(pointQ.y, pointP.y), inv)
        let x3 = subMod(subMod(mulMod(lambda, lambda), pointP.x), pointQ.x)
        let y3 = subMod(mulMod(lambda, subMod(pointP.x, x3)), pointP.y)
        return VIDECPoint(x: x3, y: y3)
    }

    /// Doubles a point on the curve.
    func double(_ point: VIDECPoint) -> VIDECPoint {
        if point.isInfinity || point.y == 0 { return .infinity }

        // λ = (3·xP² + a) / (2·yP)
        let numerator = addMod(mulMod(3, mulMod(point.x, point.x)), a)
        guard let inv = inverseMod(mulMod(2, point.y)) else { return .infinity }
        let lambda = mulMod(numerator, inv)
        let x3 = subMod(subMod(mulMod(lambda, lambda), point.x), point.x)
        let y3 = subMod(mulMod(lambda, subMod(point.x, x3)), point.y)
        return VIDECPoint(x: x3, y: y3)
    }

    /// Computes `k · point` via double-and-add in Jacobian coordinates.
    ///
    /// Jacobian arithmetic avoids a modular inversion on every point operation
    /// (the dominant cost); only the final conversion back to affine inverts
    /// once. This turns a multi-second affine scalar-multiply into milliseconds.
    func multiply(_ k: BigUInt, _ point: VIDECPoint) -> VIDECPoint {
        if point.isInfinity || k == 0 { return .infinity }
        var result = JacobianPoint.infinity
        var addend = JacobianPoint(affine: point)
        var scalar = k
        while scalar > 0 {
            if scalar & 1 == 1 { result = jacobianAdd(result, addend) }
            addend = jacobianDouble(addend)
            scalar >>= 1
        }
        return affine(from: result)
    }

    // MARK: Jacobian coordinates (X : Y : Z) ≡ affine (X/Z², Y/Z³)

    private struct JacobianPoint {
        var x: BigUInt
        var y: BigUInt
        var z: BigUInt
        static let infinity = JacobianPoint(x: 1, y: 1, z: 0)
        var isInfinity: Bool { z == 0 }

        init(x: BigUInt, y: BigUInt, z: BigUInt) {
            self.x = x; self.y = y; self.z = z
        }
        init(affine: VIDECPoint) {
            x = affine.x; y = affine.y; z = affine.isInfinity ? 0 : 1
        }
    }

    private func affine(from point: JacobianPoint) -> VIDECPoint {
        if point.isInfinity { return .infinity }
        guard let zInv = inverseMod(point.z) else { return .infinity }
        let zInv2 = mulMod(zInv, zInv)
        let zInv3 = mulMod(zInv2, zInv)
        return VIDECPoint(x: mulMod(point.x, zInv2), y: mulMod(point.y, zInv3))
    }

    private func jacobianDouble(_ p: JacobianPoint) -> JacobianPoint {
        if p.isInfinity || p.y == 0 { return .infinity }
        let xx = mulMod(p.x, p.x)
        let yy = mulMod(p.y, p.y)
        let yyyy = mulMod(yy, yy)
        let zz = mulMod(p.z, p.z)
        let s = mulMod(2, subMod(subMod(mulMod(addMod(p.x, yy), addMod(p.x, yy)), xx), yyyy))
        let m = addMod(mulMod(3, xx), mulMod(a, mulMod(zz, zz)))
        let t = subMod(mulMod(m, m), mulMod(2, s))
        let x3 = t
        let y3 = subMod(mulMod(m, subMod(s, t)), mulMod(8, yyyy))
        let z3 = subMod(subMod(mulMod(addMod(p.y, p.z), addMod(p.y, p.z)), yy), zz)
        return JacobianPoint(x: x3, y: y3, z: z3)
    }

    private func jacobianAdd(_ p: JacobianPoint, _ q: JacobianPoint) -> JacobianPoint {
        if p.isInfinity { return q }
        if q.isInfinity { return p }
        let z1z1 = mulMod(p.z, p.z)
        let z2z2 = mulMod(q.z, q.z)
        let u1 = mulMod(p.x, z2z2)
        let u2 = mulMod(q.x, z1z1)
        let s1 = mulMod(p.y, mulMod(q.z, z2z2))
        let s2 = mulMod(q.y, mulMod(p.z, z1z1))
        if u1 == u2 {
            if s1 != s2 { return .infinity } // P + (−P)
            return jacobianDouble(p)
        }
        let h = subMod(u2, u1)
        let i = mulMod(mulMod(2, h), mulMod(2, h))
        let j = mulMod(h, i)
        let r = mulMod(2, subMod(s2, s1))
        let v = mulMod(u1, i)
        let x3 = subMod(subMod(mulMod(r, r), j), mulMod(2, v))
        let y3 = subMod(mulMod(r, subMod(v, x3)), mulMod(2, mulMod(s1, j)))
        let z3 = mulMod(subMod(subMod(mulMod(addMod(p.z, q.z), addMod(p.z, q.z)), z1z1), z2z2), h)
        return JacobianPoint(x: x3, y: y3, z: z3)
    }

    /// Checks that a point satisfies the curve equation (and isn't infinity).
    func isOnCurve(_ point: VIDECPoint) -> Bool {
        if point.isInfinity { return false }
        guard point.x < p, point.y < p else { return false }
        let lhs = mulMod(point.y, point.y)
        let rhs = addMod(addMod(mulMod(mulMod(point.x, point.x), point.x), mulMod(a, point.x)), b)
        return lhs == rhs
    }

    // MARK: X9.62 uncompressed encoding (04 ‖ x ‖ y)

    /// Encodes a point as an uncompressed X9.62 octet string.
    func encodePoint(_ point: VIDECPoint) -> [UInt8] {
        [0x04] + fieldBytes(point.x) + fieldBytes(point.y)
    }

    /// Decodes an uncompressed X9.62 octet string into a point, validating it.
    func decodePoint(_ bytes: [UInt8]) -> VIDECPoint? {
        guard bytes.first == 0x04, bytes.count == 1 + 2 * fieldByteLength else { return nil }
        let x = BigUInt(Data(bytes[1...fieldByteLength]))
        let y = BigUInt(Data(bytes[(1 + fieldByteLength)...]))
        let point = VIDECPoint(x: x, y: y)
        return isOnCurve(point) ? point : nil
    }

    /// A field element as a fixed-length big-endian byte array.
    func fieldBytes(_ value: BigUInt) -> [UInt8] {
        var bytes = Array(value.serialize())
        if bytes.count > fieldByteLength {
            bytes = Array(bytes.suffix(fieldByteLength))
        } else if bytes.count < fieldByteLength {
            bytes = Array(repeating: 0, count: fieldByteLength - bytes.count) + bytes
        }
        return bytes
    }
}
