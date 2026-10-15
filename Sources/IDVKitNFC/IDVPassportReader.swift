//
//  IDVPassportReader.swift
//  IDVKit — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/IDVKit
//

import Foundation
import IDVKitCore
import IDVKitMRZ
#if canImport(CoreNFC)
    import CoreNFC
#endif

/// eMRTD (ICAO Doc 9303) passport chip reader — written from scratch for
/// IDVKit; no third-party NFC dependencies.
///
/// Milestone M2 implements, in order:
///  - ISO 7816-4 APDU layer over `NFCTagReaderSession`, with fully
///    customizable Apple-NFC-sheet messages (``IDVNFCConfiguration/displayMessage``)
///  - BAC + Secure Messaging (3DES/retail MAC via CommonCrypto)
///  - PACE (Generic Mapping)
///  - TLV data-group parsing (COM, DG1, DG2 → `IDVKitJPEG2000`, DG7, DG11,
///    DG12, DG14, DG15, SOD)
///  - Passive authentication **on by default**: SOD per-DG hash verification
///    plus DSC → CSCA chain validation against a bundled master list
///  - Chip Authentication / Active Authentication where the chip supports them
///
/// > Important: Your app must declare the NFC entitlement, the ISO7816 AIDs
/// > and `NFCReaderUsageDescription` — see the README's "Host-app
/// > requirements". A Swift package cannot add these for you.
public final class IDVPassportReader {
    /// Access-protocol, data-group and passive-authentication options.
    public let configuration: IDVNFCConfiguration

    /// Creates a reader.
    /// - Parameter configuration: The read options; the default reads the standard
    ///   data groups and verifies chip-data integrity (see ``IDVNFCConfiguration``).
    public init(configuration: IDVNFCConfiguration = .init()) {
        self.configuration = configuration
    }

    /// Whether this device can read NFC tags at all (a physical iPhone 7+; `false`
    /// on the Simulator or an unsupported device). Check before offering a chip
    /// read or a retry — retrying on a device that can't read NFC won't help.
    public static var isReadingAvailable: Bool {
        #if canImport(CoreNFC)
            NFCTagReaderSession.readingAvailable
        #else
            false
        #endif
    }

    /// Reads the passport chip. Requires a physical device with NFC.
    ///
    /// Opens an NFC session, performs BAC with the MRZ key, then reads and
    /// parses the requested data groups over Secure Messaging. iOS shows its
    /// system NFC sheet; customize its text via
    /// ``IDVNFCConfiguration/displayMessage``.
    ///
    /// - Parameter mrzKey: Access key derived from the MRZ (camera scan or
    ///   manual entry).
    /// - Returns: All requested data groups plus explicit authenticity results.
    /// - Throws: ``IDVError`` — see the `NFC` cases. `.nfcNotSupported` on the
    ///   simulator or a device without NFC (use ``IDVMockPassportReader`` there).
    public func read(mrzKey: IDVMRZKey) async throws -> IDVPassportData {
        _ = try mrzKey.seedString() // Validates the key fields up front.

        #if canImport(CoreNFC)
            // The session can be replaced mid-read (see `reconnect` below), so the
            // transceiver and progress closures go through this box.
            let box = SessionBox(IDVNFCSession(configuration: configuration))
            let operation = IDVPassportReadOperation(configuration: configuration, mrzKey: mrzKey)
            let start = Date.now
            let deadline = start.addingTimeInterval(IDVPassportReadOperation.sessionBudget)
            var freshSessionUsed = false

            // Finds the passport again after a lost tag. If CoreNFC ends the session
            // while polling (code 202, or a 200 right after the glitch), one fresh
            // session is started inside this same read; the operation then redoes
            // MF → PACE → applet and resumes every file at its saved offset.
            let reconnect: () async throws -> Void = {
                do {
                    try await box.current.reconnect(deadline: deadline)
                } catch let error as IDVError {
                    guard Self.shouldStartFreshSession(
                        after: error, sessionEnded: box.current.invalidationError != nil,
                        alreadyUsed: freshSessionUsed, now: Date.now, deadline: deadline
                    ) else { throw error }
                    freshSessionUsed = true
                    Logger.nfc.idvDebug("Session ended while reconnecting (\(error.errorDescription ?? "")); starting one fresh session")
                    await box.current.waitForInvalidation() // frees the session guard
                    let fresh = IDVNFCSession(configuration: self.configuration)
                    _ = try await fresh.connect(initialStep: .reconnecting)
                    box.current = fresh
                    Logger.nfc.idvDebug("Passport reconnected (fresh session)")
                }
            }

            do {
                _ = try await box.current.connect()
                box.current.updateMessage(.authenticating)
                let raw = try await operation.run(
                    transceive: { try await box.current.transceive($0) },
                    reconnect: reconnect,
                    onProgress: { label, fraction in
                        box.current.updateMessage(.readingDataGroup(label, progress: fraction))
                    }
                )
                // End the session before the CPU-heavy part (`finalize`), and return
                // only once the sheet is gone so the app's next alert or read can't
                // collide with a session still tearing down.
                box.current.finish(success: true)
                await box.current.waitForInvalidation()
                return operation.finalize(raw)
            } catch {
                let final = Self.sessionError(
                    for: (error as? IDVError) ?? .nfcSessionFailed(detail: error.localizedDescription),
                    elapsed: Date.now.timeIntervalSince(start)
                )
                box.current.finish(success: false, errorMessage: final.errorDescription)
                await box.current.waitForInvalidation()
                throw final
            }
        #else
            throw IDVError.nfcNotSupported
        #endif
    }

    #if canImport(CoreNFC)
        /// Reference holder so closures handed to the read operation keep talking to
        /// whichever session is current after a mid-read replacement.
        private final class SessionBox: @unchecked Sendable {
            var current: IDVNFCSession
            init(_ session: IDVNFCSession) {
                current = session
            }
        }
    #endif

    /// Whether a failed reconnect earns the single fresh session of a read: CoreNFC
    /// must have ended the session itself (not a plain "tag not found again"), it
    /// must not be a genuine user cancel, the fresh session must be unused, and the
    /// read must still be inside its budget.
    static func shouldStartFreshSession(
        after error: IDVError, sessionEnded: Bool, alreadyUsed: Bool, now: Date, deadline: Date
    ) -> Bool {
        sessionEnded && error != .nfcUserCancelled && error != .nfcBusy && !alreadyUsed && now < deadline
    }

    /// Once the read has used up CoreNFC's session budget, a transport failure —
    /// including iOS's late "System resource unavailable" — is really the ~20 s
    /// limit ending the session: report it as a timeout rather than "the passport
    /// moved" or "busy", which would send the user chasing the wrong fix.
    static func sessionError(for error: IDVError, elapsed: TimeInterval) -> IDVError {
        switch error {
        case .nfcTagConnectionLost, .nfcSessionFailed, .nfcBusy:
            elapsed >= IDVPassportReadOperation.sessionBudget ? .nfcSessionTimeout : error
        default:
            error
        }
    }
}

/// Simulator- and test-friendly reader that returns a fixture passport
/// (the ICAO 9303 specimen holder). Lets you build and demo your integration
/// without a physical device.
public final class IDVMockPassportReader {
    public init() {}

    /// Returns fixture data mirroring what ``IDVPassportReader/read(mrzKey:)``
    /// produces. Authenticity checks are reported as `notPerformed`.
    public func read(mrzKey: IDVMRZKey) async throws -> IDVPassportData {
        IDVPassportData(
            mrz: IDVMRZData(
                format: .td3, documentType: "P", issuingCountry: "UTO",
                documentNumber: mrzKey.documentNumber, nationality: "UTO",
                surname: "ERIKSSON", givenNames: "ANNA MARIA",
                birthDate: mrzKey.birthDate, expiryDate: mrzKey.expiryDate, sex: "F"
            ),
            faceImageData: nil,
            dataGroupsRead: [.com, .dg1, .sod],
            authenticity: IDVChipAuthenticityResult(
                passiveAuthentication: .notPerformed("mock reader"),
                chipAuthentication: .notPerformed(reason: "mock reader"),
                activeAuthentication: .notPerformed(reason: "mock reader")
            )
        )
    }
}
