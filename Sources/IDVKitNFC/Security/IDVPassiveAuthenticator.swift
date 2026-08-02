//
//  IDVPassiveAuthenticator.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import OSLog
import IDVKitCore

/// Performs eMRTD Passive Authentication (ICAO Doc 9303 Part 11 §5.1):
///
/// 1. Parse EF.SOD (a CMS SignedData) → the `LDSSecurityObject` hash table.
/// 2. Verify each read data group's hash matches the SOD's stored hash.
/// 3. Verify the SOD signature with the Document Signer Certificate (DSC).
/// 4. Verify the DSC chains to a trusted CSCA in the supplied trust store.
///
/// The result separates **data integrity** (steps 1–3, no trust store needed)
/// from **chain of trust** (step 4). Passive authentication proves the data was
/// signed by the issuing state and is unchanged; it does **not** by itself
/// detect a cloned chip — that is Chip/Active Authentication.
struct IDVPassiveAuthenticator {
    let configuration: IDVNFCConfiguration.PassiveAuthentication

    /// Runs passive authentication. Never throws — the outcome is always an
    /// explicit ``IDVPassiveAuthenticationResult``.
    func verify(sod: [UInt8], dataGroups: [IDVDataGroupID: [UInt8]]) -> IDVPassiveAuthenticationResult {
        if case .disabled = configuration {
            return .notPerformed("disabled in configuration")
        }

        let trustStore: IDVTrustStore? = switch configuration {
        case let .enabled(store): store
        case .integrityOnly: nil
        case .disabled: nil
        }

        do {
            // 1. Parse the SOD → LDSSecurityObject hash table + signer material.
            Logger.nfc.idvDebug("PA: parsing SOD (\(sod.count) bytes)")
            let securityObject = try IDVSecurityObject(sodBytes: sod)
            Logger.nfc.idvDebug("PA: SOD parsed, verifying")

            // 2. Compare each read data group's hash to the SOD's stored hash.
            var hashChecks: [IDVDataGroupHashCheck] = []
            var allHashesMatch = true
            for (group, bytes) in dataGroups where group != .com && group != .sod {
                guard let expected = securityObject.hash(for: group) else { continue }
                let computed = securityObject.hashAlgorithm.digest(bytes)
                let matches = computed == expected
                hashChecks.append(IDVDataGroupHashCheck(dataGroup: group, matches: matches))
                if !matches {
                    allHashesMatch = false
                }
            }

            // 3. Verify the SOD signature over its SignedAttributes.
            let signatureValid = (try? securityObject.verifySODSignature()) ?? false

            let dataIntegrity: IDVChipAuthenticityResult.CheckStatus = if !signatureValid {
                .failed(reason: "SOD signature invalid")
            } else if !allHashesMatch {
                .failed(reason: "a data group hash does not match the SOD")
            } else {
                .passed
            }

            // 4. Chain the DSC to a trusted CSCA (only if a store was supplied).
            let chainOfTrust: IDVChipAuthenticityResult.CheckStatus = if let trustStore {
                securityObject.verifyChain(to: trustStore)
            } else {
                .notPerformed(reason: "no CSCA trust store configured")
            }

            return IDVPassiveAuthenticationResult(
                dataIntegrity: dataIntegrity,
                chainOfTrust: chainOfTrust,
                dataGroupHashes: hashChecks
            )
        } catch {
            return IDVPassiveAuthenticationResult(
                dataIntegrity: .failed(reason: "could not parse SOD: \(error.localizedDescription)"),
                chainOfTrust: .notPerformed(reason: "SOD parse failed")
            )
        }
    }
}
