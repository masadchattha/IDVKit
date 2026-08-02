//
//  IDVTrustStore.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation

/// A set of trusted CSCA (Country Signing CA) certificates used as the trust
/// anchors for passport passive authentication (the DSC→CSCA chain of trust).
///
/// CSCA certificates are public government credentials. ICAO's model expects
/// trust in a CSCA to be established out-of-band, so IDVKit does not bundle a
/// master list by default — you supply the anchors you trust.
///
/// ## Getting a master list
/// A CSCA Master List (ICAO Doc 9303 Part 12) is a signed CMS blob (`.ml`) that
/// bundles hundreds of CSCAs. Load one with `IDVTrustStore(masterListCMS:)` or
/// `IDVTrustStore(masterListFileURL:)` (defined in `IDVKitNFC`). Sources:
/// - **German BSI Master List** (recommended) — ~114 countries, free for
///   commercial use. `https://www.bsi.bund.de/dok/masterlist` (see BSI's CSCA
///   page for the current download + license terms).
/// - **ICAO PKD Master List** — the canonical list.
///   `https://www.icao.int/icao-pkd/icao-master-list`
///
/// The CSCA is never carried in the passport, so it must come from a master
/// list. Countries that don't participate in the ICAO PKD (e.g. Pakistan) are
/// absent from both the BSI and ICAO lists — obtain their CSCA directly from the
/// issuing authority and add it via `certificatesDER`/`pem`.
///
/// Alternatively, supply raw DER/PEM certificates directly via the other
/// initializers. A snapshot goes stale as countries rotate CSCAs, so refresh it
/// periodically.
public struct IDVTrustStore: Sendable {
    /// DER-encoded CSCA certificates that act as trust anchors.
    public let anchorsDER: [Data]

    /// Builds a trust store from DER-encoded certificates.
    public init(certificatesDER: [Data]) {
        anchorsDER = certificatesDER
    }

    /// Builds a trust store from one or more concatenated PEM blocks.
    /// Every `-----BEGIN CERTIFICATE-----` block is decoded.
    public init(pem: String) {
        anchorsDER = IDVTrustStore.decodePEMCertificates(pem)
    }

    /// Builds a trust store from a PEM file on disk (e.g. a bundled snapshot).
    public init(pemFileURL url: URL) throws {
        let pem = try String(contentsOf: url, encoding: .utf8)
        anchorsDER = IDVTrustStore.decodePEMCertificates(pem)
    }

    /// An empty store — passive authentication will verify data integrity only.
    public static let empty = IDVTrustStore(certificatesDER: [])

    /// Extracts every certificate's DER bytes from concatenated PEM text.
    static func decodePEMCertificates(_ pem: String) -> [Data] {
        var results: [Data] = []
        let begin = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        var remainder = Substring(pem)
        while let beginRange = remainder.range(of: begin),
              let endRange = remainder.range(of: end) {
            let base64 = remainder[beginRange.upperBound ..< endRange.lowerBound]
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            if let data = Data(base64Encoded: base64) {
                results.append(data)
            }
            remainder = remainder[endRange.upperBound...]
        }
        return results
    }
}
