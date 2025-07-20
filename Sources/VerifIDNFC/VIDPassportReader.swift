//
//  VIDPassportReader.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation
import VerifIDCore
import VerifIDMRZ

/// eMRTD (ICAO Doc 9303) passport chip reader — written from scratch for
/// VerifID; no third-party NFC dependencies.
///
/// Milestone M2 implements, in order:
///  - ISO 7816-4 APDU layer over `NFCTagReaderSession`, with fully
///    customizable Apple-NFC-sheet messages (``VIDNFCConfiguration/displayMessage``)
///  - BAC + Secure Messaging (3DES/retail MAC via CommonCrypto)
///  - PACE (Generic Mapping)
///  - TLV data-group parsing (COM, DG1, DG2 → `VerifIDJPEG2000`, DG7, DG11,
///    DG12, DG14, DG15, SOD)
///  - Passive authentication **on by default**: SOD per-DG hash verification
///    plus DSC → CSCA chain validation against a bundled master list
///  - Chip Authentication / Active Authentication where the chip supports them
///
/// > Important: Your app must declare the NFC entitlement, the ISO7816 AIDs
/// > and `NFCReaderUsageDescription` — see the README's "Host-app
/// > requirements". A Swift package cannot add these for you.
public final class VIDPassportReader {
    /// Access-protocol, data-group and passive-authentication options.
    public let configuration: VIDNFCConfiguration

    /// Creates a reader.
    /// - Parameter configuration: The read options; the default reads the standard
    ///   data groups and verifies chip-data integrity (see ``VIDNFCConfiguration``).
    public init(configuration: VIDNFCConfiguration = .init()) {
        self.configuration = configuration
    }

    /// Reads the passport chip. Requires a physical device with NFC.
    ///
    /// Opens an NFC session, performs BAC with the MRZ key, then reads and
    /// parses the requested data groups over Secure Messaging. iOS shows its
    /// system NFC sheet; customize its text via
    /// ``VIDNFCConfiguration/displayMessage``.
    ///
    /// - Parameter mrzKey: Access key derived from the MRZ (camera scan or
    ///   manual entry).
    /// - Returns: All requested data groups plus explicit authenticity results.
    /// - Throws: ``VIDError`` — see the `NFC` cases. `.nfcNotSupported` on the
    ///   simulator or a device without NFC (use ``VIDMockPassportReader`` there).
    public func read(mrzKey: VIDMRZKey) async throws -> VIDPassportData {
        _ = try mrzKey.seedString() // Validates the key fields up front.

        #if canImport(CoreNFC)
            let session = VIDNFCSession(configuration: configuration)
            _ = try await session.connect()
            session.updateMessage(.authenticating)

            let operation = VIDPassportReadOperation(configuration: configuration, mrzKey: mrzKey)
            do {
                let passport = try await operation.run(
                    transceive: { try await session.transceive($0) },
                    onProgress: { label, fraction in
                        session.updateMessage(.readingDataGroup(label, progress: fraction))
                    }
                )
                session.finish(success: true)
                return passport
            } catch let error as VIDError {
                session.finish(success: false, errorMessage: error.errorDescription)
                throw error
            } catch {
                session.finish(success: false)
                throw VIDError.nfcSessionFailed(detail: error.localizedDescription)
            }
        #else
            throw VIDError.nfcNotSupported
        #endif
    }
}

/// Simulator- and test-friendly reader that returns a fixture passport
/// (the ICAO 9303 specimen holder). Lets you build and demo your integration
/// without a physical device.
public final class VIDMockPassportReader {
    public init() {}

    /// Returns fixture data mirroring what ``VIDPassportReader/read(mrzKey:)``
    /// produces. Authenticity checks are reported as `notPerformed`.
    public func read(mrzKey: VIDMRZKey) async throws -> VIDPassportData {
        VIDPassportData(
            mrz: VIDMRZData(
                format: .td3, documentType: "P", issuingCountry: "UTO",
                documentNumber: mrzKey.documentNumber, nationality: "UTO",
                surname: "ERIKSSON", givenNames: "ANNA MARIA",
                birthDate: mrzKey.birthDate, expiryDate: mrzKey.expiryDate, sex: "F"
            ),
            faceImageData: nil,
            dataGroupsRead: [.com, .dg1, .sod],
            authenticity: VIDChipAuthenticityResult(
                passiveAuthentication: .notPerformed("mock reader"),
                chipAuthentication: .notPerformed(reason: "mock reader"),
                activeAuthentication: .notPerformed(reason: "mock reader")
            )
        )
    }
}
