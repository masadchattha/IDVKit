//
//  VIDModels.swift
//  VerifID — Open-source identity verification for iOS
//
//  Created by Muhammad Asad on 03/07/2026.
//  Copyright © 2026 Muhammad Asad. Licensed under the MIT License.
//  https://github.com/masadchattha/verifid-ios
//

import Foundation

// MARK: - Document data

/// Parsed machine-readable zone data as defined by ICAO Doc 9303.
///
/// Produced by ``VIDMRZParser`` (camera scan or manual entry) and by the
/// chip's DG1 data group. All date fields keep the raw `YYMMDD` form printed
/// in the MRZ; convert to `Date` in your app if needed.
public struct VIDMRZData: Sendable, Equatable, Codable {
    /// Physical MRZ layout variants defined by ICAO Doc 9303.
    public enum Format: String, Sendable, Codable {
        /// ID cards — three lines of 30 characters.
        case td1
        /// Older ID documents — two lines of 36 characters.
        case td2
        /// Passports — two lines of 44 characters.
        case td3
    }

    public var format: Format
    /// Document type code, e.g. `P` for passport.
    public var documentType: String
    /// ISO 3166-1 alpha-3 issuing state, e.g. `PAK`, `DEU`.
    public var issuingCountry: String
    /// Document number with filler characters removed.
    public var documentNumber: String
    /// ISO 3166-1 alpha-3 nationality of the holder.
    public var nationality: String
    /// Primary identifier (surname) with fillers converted to spaces.
    public var surname: String
    /// Secondary identifier (given names) with fillers converted to spaces.
    public var givenNames: String
    /// Date of birth as printed in the MRZ (`YYMMDD`).
    public var birthDate: String
    /// Date of expiry as printed in the MRZ (`YYMMDD`).
    public var expiryDate: String
    /// Sex marker: `M`, `F`, or empty when unspecified (`<`).
    public var sex: String
    /// Optional data element (personal number on many passports).
    public var optionalData: String

    public init(
        format: Format, documentType: String, issuingCountry: String,
        documentNumber: String, nationality: String, surname: String,
        givenNames: String, birthDate: String, expiryDate: String,
        sex: String, optionalData: String = ""
    ) {
        self.format = format
        self.documentType = documentType
        self.issuingCountry = issuingCountry
        self.documentNumber = documentNumber
        self.nationality = nationality
        self.surname = surname
        self.givenNames = givenNames
        self.birthDate = birthDate
        self.expiryDate = expiryDate
        self.sex = sex
        self.optionalData = optionalData
    }

    /// The document category inferred from the MRZ, per ICAO Doc 9303.
    ///
    /// This is **reliable at the passport-vs-card level**: a TD3 layout, or a
    /// document code beginning with `P`, is a passport; everything else is a
    /// card. It deliberately does **not** try to separate a national ID card
    /// from a residence permit — both use the TD1 layout and the distinguishing
    /// code is issuer-defined rather than standardised, so both report
    /// ``VIDVerificationStep/DocumentKind/idCard``.
    public var detectedDocumentKind: VIDVerificationStep.DocumentKind {
        let code = documentType.uppercased()
        // A passport booklet is always TD3; `P…` is the passport code; `IP` is a
        // passport *card* carried on the TD1 layout.
        if format == .td3 || code.hasPrefix("P") || code == "IP" {
            return .passport
        }
        return .idCard
    }

    /// Whether this MRZ is consistent with `kind`.
    ///
    /// `.any` always matches. An ID card and a residence permit are treated as
    /// interchangeable because the MRZ cannot tell them apart (ICAO Doc 9303).
    public func matches(_ kind: VIDVerificationStep.DocumentKind) -> Bool {
        switch kind {
        case .any: true
        case .passport: detectedDocumentKind == .passport
        case .idCard, .residencePermit: detectedDocumentKind != .passport
        }
    }
}

/// Everything read from an eMRTD (passport) chip.
public struct VIDPassportData: Sendable, Equatable {
    /// MRZ data parsed from the chip's DG1 data group.
    public var mrz: VIDMRZData
    /// The holder's photo from DG2, re-encoded as JPEG data.
    /// JPEG2000 originals are decoded internally by ``VIDJPEG2000Decoder``.
    public var faceImageData: Data?
    /// Data groups that were present on the chip and successfully read.
    public var dataGroupsRead: [VIDDataGroupID]
    /// Chip-genuineness verification results. Never optional —
    /// "not performed" is always explicit, never silent.
    public var authenticity: VIDChipAuthenticityResult

    public init(
        mrz: VIDMRZData, faceImageData: Data?,
        dataGroupsRead: [VIDDataGroupID], authenticity: VIDChipAuthenticityResult
    ) {
        self.mrz = mrz
        self.faceImageData = faceImageData
        self.dataGroupsRead = dataGroupsRead
        self.authenticity = authenticity
    }
}

/// LDS data groups defined by ICAO Doc 9303 part 10.
public enum VIDDataGroupID: String, Sendable, Equatable, CaseIterable {
    case com = "COM"
    /// MRZ mirror.
    case dg1 = "DG1"
    /// Encoded face image of the holder.
    case dg2 = "DG2"
    /// Displayed signature or usual mark.
    case dg7 = "DG7"
    /// Additional personal details.
    case dg11 = "DG11"
    /// Additional document details.
    case dg12 = "DG12"
    /// Security options (Chip Authentication public key).
    case dg14 = "DG14"
    /// Active Authentication public key.
    case dg15 = "DG15"
    /// Document Security Object — signed hashes of all data groups.
    case sod = "SOD"
}

// MARK: - Security results

/// Outcome of the chip-genuineness checks.
public struct VIDChipAuthenticityResult: Sendable, Equatable {
    /// Result of one individual security check.
    public enum CheckStatus: Sendable, Equatable {
        case passed
        case failed(reason: String)
        /// The check was skipped (e.g. disabled in configuration, no trust store).
        case notPerformed(reason: String)
        /// The chip does not implement this protocol.
        case notSupportedByChip

        /// `true` only when the check passed.
        public var isPassed: Bool {
            self == .passed
        }

        /// The human-readable reason for a non-passing status, if any.
        public var reason: String? {
            switch self {
            case let .failed(reason), let .notPerformed(reason): reason
            case .passed, .notSupportedByChip: nil
            }
        }
    }

    /// Passive authentication result (ICAO 9303 Part 11 §5.1). Proves the data
    /// was signed by the issuing state and is unchanged.
    public var passiveAuthentication: VIDPassiveAuthenticationResult
    /// Chip Authentication (BSI TR-03110). Proves the chip is not cloned.
    public var chipAuthentication: CheckStatus
    /// Active Authentication (DG15 challenge/response clone check).
    public var activeAuthentication: CheckStatus

    public init(
        passiveAuthentication: VIDPassiveAuthenticationResult,
        chipAuthentication: CheckStatus,
        activeAuthentication: CheckStatus
    ) {
        self.passiveAuthentication = passiveAuthentication
        self.chipAuthentication = chipAuthentication
        self.activeAuthentication = activeAuthentication
    }
}

/// Passive authentication has two independent halves, reported separately so a
/// caller without a CSCA trust store still learns whether the data is intact.
public struct VIDPassiveAuthenticationResult: Sendable, Equatable {
    /// The data-group hashes match the SOD **and** the SOD signature is valid.
    /// Establishes that the data on the chip was not altered. Needs no trust store.
    public var dataIntegrity: VIDChipAuthenticityResult.CheckStatus

    /// The Document Signer Certificate chains to a trusted CSCA. Establishes
    /// that a genuine issuing state signed the data. Needs a CSCA trust store.
    public var chainOfTrust: VIDChipAuthenticityResult.CheckStatus

    /// Per-data-group hash comparison detail (SOD hash vs computed hash).
    public var dataGroupHashes: [VIDDataGroupHashCheck]

    /// `true` only when both halves passed — the strongest guarantee.
    public var isFullyVerified: Bool {
        dataIntegrity == .passed && chainOfTrust == .passed
    }

    public init(
        dataIntegrity: VIDChipAuthenticityResult.CheckStatus,
        chainOfTrust: VIDChipAuthenticityResult.CheckStatus,
        dataGroupHashes: [VIDDataGroupHashCheck] = []
    ) {
        self.dataIntegrity = dataIntegrity
        self.chainOfTrust = chainOfTrust
        self.dataGroupHashes = dataGroupHashes
    }

    /// A result where nothing was verified, with a reason.
    public static func notPerformed(_ reason: String) -> VIDPassiveAuthenticationResult {
        VIDPassiveAuthenticationResult(
            dataIntegrity: .notPerformed(reason: reason),
            chainOfTrust: .notPerformed(reason: reason)
        )
    }
}

/// One data group's hash comparison against the SOD.
public struct VIDDataGroupHashCheck: Sendable, Equatable {
    public var dataGroup: VIDDataGroupID
    public var matches: Bool

    public init(dataGroup: VIDDataGroupID, matches: Bool) {
        self.dataGroup = dataGroup
        self.matches = matches
    }
}

// MARK: - Face results

/// Rich face-match outcome. VerifID always surfaces the similarity score and
/// the threshold that was applied — never a bare yes/no.
public struct VIDFaceMatchResult: Sendable, Equatable {
    /// Whether ``similarity`` cleared ``thresholdUsed``.
    public var isMatch: Bool
    /// Cosine similarity between the two face embeddings, in −1…1.
    public var similarity: Float
    /// The decision threshold from ``VIDFaceConfiguration/matchThreshold``.
    public var thresholdUsed: Float
    /// The document (reference) face used for comparison, as JPEG data.
    public var referenceImageData: Data
    /// The live selfie used for comparison, as JPEG data.
    public var liveImageData: Data

    public init(
        isMatch: Bool, similarity: Float, thresholdUsed: Float,
        referenceImageData: Data, liveImageData: Data
    ) {
        self.isMatch = isMatch
        self.similarity = similarity
        self.thresholdUsed = thresholdUsed
        self.referenceImageData = referenceImageData
        self.liveImageData = liveImageData
    }
}

/// Result of an active-liveness session.
public struct VIDLivenessOutcome: Sendable, Equatable {
    public var passed: Bool
    /// Raw values of the ``VIDLivenessChallenge`` cases the user completed.
    public var challengesCompleted: [String]
    /// Neutral still captured after liveness (JPEG), used for face matching.
    public var capturedImageData: Data?

    public init(passed: Bool, challengesCompleted: [String], capturedImageData: Data?) {
        self.passed = passed
        self.challengesCompleted = challengesCompleted
        self.capturedImageData = capturedImageData
    }
}

// MARK: - Flow result

/// Final result delivered by the drop-in flow, or assembled manually when
/// using the headless modules.
public enum VIDVerificationResult: Sendable {
    case verified(VIDVerificationOutcome)
    case failed(VIDError)
    case cancelled
}

/// The output of a verification flow.
///
/// `liveness` and `faceMatch` are optional because the face step is not run in
/// every configuration (and ships in a later milestone); `document` is always
/// present once the chip has been read.
public struct VIDVerificationOutcome: Sendable {
    public var document: VIDPassportData
    public var liveness: VIDLivenessOutcome?
    public var faceMatch: VIDFaceMatchResult?

    public init(
        document: VIDPassportData,
        liveness: VIDLivenessOutcome? = nil,
        faceMatch: VIDFaceMatchResult? = nil
    ) {
        self.document = document
        self.liveness = liveness
        self.faceMatch = faceMatch
    }
}
