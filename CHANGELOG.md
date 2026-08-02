# Changelog

All notable changes to IDVKit are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com); versioning follows SemVer.

## [Unreleased]
### Added
- **On-device milestone: the full document + chip read works on a real passport.**
  BAC/PACE, secure messaging, and data-group reading (COM/DG1/DG2/SOD) verified on hardware.
- **RSASSA-PSS Document Signer Certificates** are now verified via `_CryptoExtras` (SHA-256/384/512
  + the SHA-1 default), parsing the RSASSA-PSS-params hash — fixes "Chip data not verified" on
  passports whose DSC signs with PSS (which swift-certificates cannot verify).
- **MRZ dates** (`YYMMDD`) are parsed to `Date` with century inference and exposed as locale-aware
  formatted strings (`IDVMRZData.dateOfBirth` / `.dateOfExpiry` / `.formattedDateOfBirth` /
  `.formattedDateOfExpiry` / `.isExpired` / `.sexDescription`).
- **Drop-in flow completed**: Intro → MRZ scan → NFC read → themeable result screen (holder photo,
  formatted data rows, chip-verified state with reasons, "scanned MRZ matches the chip"). The result
  badge distinguishes verified / intact-but-no-trust-store / not-verified with the failure reason.
- Example app shows the decoded face image and formatted dates.

- **PACE (PACE-ECDH-GM) — the access protocol many modern chips require instead of BAC:**
  - Curve-agnostic elliptic-curve math (brainpool P256/P384/P512 + NIST P-256/384/521),
    which Apple's crypto stack cannot do; Jacobian-coordinate scalar multiplication
  - PACE key derivation, AES-CMAC/AES-CBC, mutual-authentication tokens
  - EF.CardAccess `PACEInfo` parsing; the 5-step General Authenticate handshake
  - AES Secure Messaging (16-byte SSC, per-message IV = E(KS_Enc, SSC), AES-CMAC)
  - **The complete handshake is validated end-to-end against the ICAO Doc 9303 Part 11
    Appendix G worked example** — every EC computation, both session keys, and both
    T_IFD/T_PICC tokens match, reproducing Appendix G's exact KS_Enc/KS_MAC
  - New `accessProtocol` config (`.automatic` prefers PACE then falls back to BAC,
    `.paceOnly`, `.bacOnly`); one new dependency (attaswift/BigInt, pure Swift, MIT)
  - Honest scope: brainpool P256/384/512 + all NIST curves covered; classic MODP-DH and
    Integrated/Chip-Auth Mapping are not yet implemented
- **Passive authentication (ICAO 9303 Part 11 §5.1)** — verify the passport chip's data:
  - Hand-parses EF.SOD (CMS SignedData) and the LDSSecurityObject with Apple's `swift-asn1`
  - **Data integrity**: every data-group hash is checked against the SOD, and the SOD's
    CMS signature is verified with the Document Signer Certificate (SignedAttributes
    re-tagged per RFC 5652, messageDigest confirmed) — no trust store required
  - **Chain of trust**: the DSC is validated against host-supplied CSCA anchors
    (`IDVTrustStore`) via Apple's `swift-certificates`
  - The two halves are reported **separately** (`dataIntegrity` / `chainOfTrust`) so an
    app without a CSCA store still gets integrity verification, not a misleading fail
  - Honest handling of the gaps: RSA-PSS / ECDSA-SHA1 / brainpool report `notPerformed`
    with a reason rather than a false result
  - New public API: `IDVTrustStore`, `IDVPassiveAuthenticationResult`, `IDVDataGroupHashCheck`;
    `passiveAuthentication` config is now `.enabled(cscaTrustStore:)` / `.integrityOnly` / `.disabled`
- **NFC passport reading (eMRTD / ICAO 9303) — the M2 crown jewel, from scratch, no third-party NFC library:**
  - BER-TLV parser (short/long-form lengths, nested constructed objects, multi-byte tags)
  - ISO 7816-4 APDU command/response encoding with status-word handling
  - 3DES + ISO 9797-1 retail MAC + ICAO KDF over CommonCrypto (no crypto dependency)
  - BAC mutual authentication and Secure Messaging (SSC, DO87/97/99/8E protect/unprotect)
  - **Validated byte-for-byte against the ICAO Doc 9303 Part 11 Appendix D worked example** —
    K_ENC/K_MAC, E.IFD, retail MAC, session KS_ENC/KS_MAC/SSC, and the SELECT/READ BINARY
    Secure Messaging vectors are all unit tests.
  - Data-group parsing: COM tag list, DG1 → `IDVMRZData`, DG2 face image (ISO 19794-5 →
    JPEG/JPEG2000 via magic-byte scan → decoded through `IDVJPEG2000Decoder`)
  - `NFCTagReaderSession` wrapper with customizable system-sheet messages, chunked READ BINARY
    within CoreNFC's connection budget, `IDVReaderError` → `IDVError` mapping
  - `IDVPassportReader.read(mrzKey:)` now performs a real end-to-end chip read on device
- Example app: "Read passport chip via NFC" wired after an MRZ scan.

### Notes
- Passive authentication (SOD → CSCA chain) is the next M2 increment; the reader reports it
  explicitly as `notPerformed` rather than silently skipping it.

## [0.1.0-scaffold]
### Added
- `IDV`-prefixed public API surface: models, configuration (incl. `IDVBrandingConfiguration`
  for host-app icon/name), `IDVTheme` design tokens, typed `IDVError`, `IDVLog`.
- **MRZ scanning (functional)**: `IDVMRZScanner` (AVFoundation + Vision, ICAO 9303
  check-digit validation per frame, torch, region-of-interest) and the drop-in
  `IDVMRZScannerView` (guided document frame, animated scan line, haptics).
- Own ICAO 9303 parser: check digits, TD3 parsing, BAC key-seed derivation —
  validated against the spec's worked examples.
- **JPEG2000 decoding (functional)**: OpenJPEG 2.5.4 vendored as an SPM C target
  (device + simulator + Catalyst) with a safe, throwing `IDVJPEG2000Decoder`.
- Drop-in flow shell `IDVVerificationFlowView` with theming, branding and the
  working MRZ step; mock passport reader for simulator development.
- Example app under `Examples/IDVKitExample` (XcodeGen).
