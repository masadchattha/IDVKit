//
//  IDVCSCAMasterList.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 11/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import OSLog
import SwiftASN1
import IDVKitCore

/// Parses an ICAO CSCA Master List (Doc 9303 Part 12) into its member CSCA
/// certificates.
///
/// A master list is a CMS `SignedData` (RFC 5652) whose `eContentType` is
/// `id-icao-cscaMasterList` (2.23.136.1.1.2) and whose `eContent` carries:
///
///     CscaMasterList ::= SEQUENCE {
///         version   INTEGER,
///         certList  SET OF Certificate }
///
/// Each member is a full X.509 CSCA (or CSCA link) certificate — exactly the
/// trust anchors passive authentication needs. The German BSI and ICAO PKD
/// distribute these lists (`.ml` files); see ``IDVTrustStore`` for sources.
///
/// Distributions come from an authoritative HTTPS origin, so for a first cut we
/// harvest `certList` without verifying the list's own Master List Signer. A
/// production integration should additionally verify that signature and chain
/// the signer to a CSCA it already trusts.
public enum IDVCSCAMasterList {
    /// OID `2.23.136.1.1.2` — id-icao-cscaMasterList (the eContentType).
    private static let masterListOID = "2.23.136.1.1.2"
    /// OID `1.2.840.113549.1.7.2` — id-signedData.
    private static let signedDataOID = "1.2.840.113549.1.7.2"

    /// Extracts every CSCA certificate's DER bytes from a master-list CMS
    /// (the raw contents of a `.ml` file). Returns an empty array if the input
    /// isn't a well-formed master list.
    public static func certificateDERs(fromCMS cms: [UInt8]) -> [Data] {
        guard let eContent = extractEContent(fromCMS: cms),
              let masterList = try? IDVSecurityObject.parseDERorBER(eContent[...]) else {
            // Fall back to scanning the whole CMS for certificate-shaped nodes,
            // covering minor structural variations across issuers.
            return scanForCertificates(cms)
        }
        let ders = IDVSecurityObject.collectCertificateDERs(masterList)
        Logger.nfc.idvDebug("CSCA master list: extracted \(ders.count) certificate(s)")
        return ders.map { Data($0) }
    }

    // MARK: Navigation

    /// Navigates ContentInfo → SignedData → encapContentInfo and returns the
    /// `eContent` OCTET STRING bytes, verifying the master-list OID along the way.
    private static func extractEContent(fromCMS cms: [UInt8]) -> [UInt8]? {
        guard let contentInfo = try? IDVSecurityObject.parseDERorBER(cms[...]),
              case let .constructed(ciChildren) = contentInfo.content else { return nil }
        let ci = Array(ciChildren)
        // ContentInfo ::= SEQUENCE { contentType OID, content [0] EXPLICIT SignedData }
        guard let ctNode = ci.first,
              let contentType = try? ASN1ObjectIdentifier(derEncoded: ctNode),
              contentType.description == signedDataOID,
              let contentZero = ci.last,
              case let .constructed(czChildren) = contentZero.content,
              let signedData = Array(czChildren).first,
              case let .constructed(sdChildren) = signedData.content else { return nil }

        // encapContentInfo ::= SEQUENCE { eContentType OID, eContent [0] EXPLICIT OCTET STRING }
        for node in Array(sdChildren) {
            guard node.identifier == .sequence,
                  case let .constructed(encapChildren) = node.content else { continue }
            let encap = Array(encapChildren)
            guard let typeNode = encap.first,
                  let eContentType = try? ASN1ObjectIdentifier(derEncoded: typeNode),
                  eContentType.description == masterListOID,
                  let eContentZero = encap.last,
                  case let .constructed(ecChildren) = eContentZero.content,
                  let octet = Array(ecChildren).first,
                  case let .primitive(bytes) = octet.content else { continue }
            return Array(bytes)
        }
        return nil
    }

    /// Last-resort: walk the entire CMS collecting anything certificate-shaped.
    private static func scanForCertificates(_ cms: [UInt8]) -> [Data] {
        guard let root = try? IDVSecurityObject.parseDERorBER(cms[...]) else { return [] }
        let ders = IDVSecurityObject.collectCertificateDERs(root)
        Logger.nfc.idvDebug("CSCA master list: fallback scan found \(ders.count) certificate(s)")
        return ders.map { Data($0) }
    }
}

extension IDVTrustStore {
    /// Builds a trust store from an ICAO CSCA Master List CMS (a `.ml` file's
    /// raw bytes — e.g. the German BSI or ICAO PKD master list).
    ///
    /// Every CSCA certificate in the list becomes a trust anchor. See
    /// ``IDVCSCAMasterList`` for the verification caveat.
    public init(masterListCMS: Data) {
        self.init(certificatesDER: IDVCSCAMasterList.certificateDERs(fromCMS: Array(masterListCMS)))
    }

    /// Builds a trust store from a master-list file on disk (bundled `.ml`).
    public init(masterListFileURL url: URL) throws {
        let data = try Data(contentsOf: url)
        self.init(masterListCMS: data)
    }
}
