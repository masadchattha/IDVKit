//
//  IDVPACEInfo.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore
import SwiftASN1

/// A parsed `PACEInfo` from the chip's `EF.CardAccess` (ICAO Doc 9303 Part 11
/// §9.2.1): the PACE protocol OID, version, and the domain-parameter id.
struct IDVPACEInfo: Equatable {
    let protocolOID: String
    let version: Int
    let parameterId: Int?

    /// The mapping used by the protocol. IDVKit implements Generic Mapping.
    var mapping: Mapping? {
        Self.mapping(for: protocolOID)
    }

    /// The symmetric cipher/keying strength the protocol selects.
    var cipher: IDVPACEKeyDerivation.Cipher? {
        Self.cipher(for: protocolOID)
    }

    enum Mapping { case generic, integrated, chipAuthentication }

    /// Finds the `PACEInfo` inside an `EF.CardAccess` SecurityInfos SET.
    /// Prefers an ECDH Generic Mapping entry, which is what IDVKit supports.
    static func parse(cardAccess: [UInt8]) throws -> IDVPACEInfo {
        let root = try IDVSecurityObject.parseDERorBER(cardAccess[...])
        guard case let .constructed(entries) = root.content else {
            throw IDVError.accessControlFailed(detail: "EF.CardAccess is not a SET")
        }

        var found: [IDVPACEInfo] = []
        for entry in entries {
            guard case let .constructed(fields) = entry.content else { continue }
            var iterator = fields.makeIterator()
            guard let oidNode = iterator.next(),
                  let oid = try? ASN1ObjectIdentifier(derEncoded: oidNode),
                  oid.description.hasPrefix("0.4.0.127.0.7.2.2.4") else { continue }

            // PACEInfo ::= SEQUENCE { protocol OID, version INTEGER, parameterId INTEGER OPTIONAL }
            let version = (try? iterator.next().map { try Int(derEncoded: $0) }) ?? nil
            let parameterId = (try? iterator.next().map { try Int(derEncoded: $0) }) ?? nil
            found.append(IDVPACEInfo(
                protocolOID: oid.description, version: version ?? 2, parameterId: parameterId
            ))
        }

        guard let best = found.first(where: { $0.mapping == .generic }) ?? found.first else {
            throw IDVError.accessControlFailed(detail: "no PACEInfo in EF.CardAccess")
        }
        return best
    }

    // MARK: OID classification

    /// The 10-byte DER encoding of the protocol OID (used inside the 7F49 token
    /// object).
    var protocolOIDBytes: [UInt8]? {
        try? Array(ASN1ObjectIdentifier(dotRepresentation: protocolOID).derBytes())
    }

    static func mapping(for oid: String) -> Mapping? {
        // id-PACE-{DH,ECDH}-GM = ...4.1 / ...4.2, IM = ...4.3 / ...4.4, CAM = ...4.5 / ...4.6
        if oid.hasPrefix("0.4.0.127.0.7.2.2.4.1") || oid.hasPrefix("0.4.0.127.0.7.2.2.4.2") {
            return .generic
        }
        if oid.hasPrefix("0.4.0.127.0.7.2.2.4.3") || oid.hasPrefix("0.4.0.127.0.7.2.2.4.4") {
            return .integrated
        }
        if oid.hasPrefix("0.4.0.127.0.7.2.2.4.5") || oid.hasPrefix("0.4.0.127.0.7.2.2.4.6") {
            return .chipAuthentication
        }
        return nil
    }

    static func cipher(for oid: String) -> IDVPACEKeyDerivation.Cipher? {
        // Trailing component: 1 = 3DES, 2 = AES-128, 3 = AES-192, 4 = AES-256.
        switch oid.split(separator: ".").last {
        case "2": .aes128
        case "3": .aes192
        case "4": .aes256
        default: nil // 3DES (1) not used by IDVKit's AES SM path
        }
    }

    /// `true` when this is an EC (not classic DH) Generic Mapping protocol.
    var isECDH: Bool {
        protocolOID.hasPrefix("0.4.0.127.0.7.2.2.4.2")
    }
}

extension ASN1ObjectIdentifier {
    /// DER content bytes of the OID (without the outer 0x06 tag/length).
    fileprivate func derBytes() throws -> ArraySlice<UInt8> {
        var serializer = DER.Serializer()
        try serialize(into: &serializer)
        // Strip tag (1) + length (1) for a short OID.
        let full = serializer.serializedBytes
        guard full.count > 2 else { return full[...] }
        return full[2...]
    }
}
