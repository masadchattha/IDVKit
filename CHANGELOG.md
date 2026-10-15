# Changelog

All notable changes to IDVKit are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com); versioning follows SemVer.

## [1.0.0] - 2026-10-14

First stable, API-stable release. From here, pin **Up to Next Major from `1.0.0`**;
breaking changes ship only in `2.0.0`. Hardened against the Votari device
integration (iOS 26, Pakistani passport: PACE-ECDH-GM-AES-256, raw-J2K DG2, AA).

### Added — read reliability & data fidelity
- **Resilient chip read.** READ BINARY now defaults to `0xA0` (160 B — the size that
  reads most reliably across chips), configurable via `IDVNFCConfiguration.readChunkSize`.
  A dropped response, a tag-response glitch, or a `6C xx` / `67 00` length correction
  now **re-opens the secure channel (PACE/BAC, + Chip Authentication if it had run),
  re-selects the file, and resumes from the last good offset** — up to 3 retries per
  file, inside CoreNFC's ~20 s budget — instead of failing the whole read. `nfcSessionFailed`
  surfaces only once retries are exhausted.
- **Resilient handshake.** An APDU that goes unanswered now fails after ~3 s instead of
  pinning the read until CoreNFC's ~20 s session limit; PACE/BAC and Chip Authentication
  are then re-run from a fresh applet SELECT (up to 3 tries, inside the session deadline),
  so a stalled chip costs seconds, not the whole scan. The chip callback, the timeout and
  session invalidation race for one continuation that is resumed exactly once. With
  `IDVLog.isEnabled`, every handshake APDU logs its step name (`MSE:Set AT`, `GA nonce`,
  `GA map`, `GA key`, `GA mutual auth`, `CA MSE`, `CA GA`, …) and round-trip time in ms.
  A transport failure after the session budget — including iOS's "System resource
  unavailable" — now surfaces as `nfcSessionTimeout`, not "the passport moved".
- **PACE actually runs.** iOS leaves the eMRTD applet selected on connect, where selecting
  EF.CardAccess answers `6A82`, so every read silently fell back to BAC. The channel setup
  now follows ICAO 9303 Part 11's order: `SELECT MF` → EF.CardAccess → PACE → applet
  `SELECT` under the new secure channel → files (a chip that refuses `SELECT MF` is read as
  before). BAC is used only when EF.CardAccess is really absent or PACE itself fails; a
  transport glitch during PACE re-runs PACE via the handshake retry instead of downgrading.
  Session invalidation now also logs the raw `NFCReaderError` code and ms since the last APDU.
- **Session hygiene.** One NFC session at a time: a `read()` while another is active throws
  the new `IDVError.nfcBusy` before touching CoreNFC, and the slot is freed only once the
  old session's invalidation callback has fired. A start that iOS refuses with "System
  resource unavailable" is retried once after 1 s, then reported as `nfcBusy` (not a
  timeout). `read()` returns only after the system sheet is gone (capped at 2 s), so the
  app's next alert or scan never collides with a session still tearing down. Delegate
  callbacks run on a private serial queue, never on main.
- **Work after the chip, not during.** The DG2 decode and passive authentication now run
  after the session has ended (`IDVPassportReadOperation.finalize`); decoding with the field
  live idled the chip long enough to drop the connection.
- **Reconnect on a lost tag.** When the connection really drops, the SDK polls for the
  passport again ("Keep holding your passport…", `ReadStep.reconnecting`), reconnects, redoes
  the handshake and resumes at the saved offset — bounded by the session deadline — instead
  of burning its retries against a dead connection. A transport error during Active
  Authentication reports `.notPerformed`, never `.failed`.
- **Fresh session after a dead reconnect.** If CoreNFC ends the session while the SDK is
  polling for a lost passport (code 202, or a code 200 within 1.5 s of a transport glitch —
  that is iOS, not the user), one fresh `NFCTagReaderSession` is started inside the same
  `read()` ("Keep holding your passport…"), the handshake is redone and every file resumes at
  its saved offset. Once per read, inside a 30 s overall budget; then `nfcTagConnectionLost`.
  Every CoreNFC code now maps to an IDVKit case (201 → `nfcSessionTimeout`, 202/1xx →
  `nfcTagConnectionLost`, 203 → `nfcBusy`) — raw iOS wording never reaches the user. The
  invalidation waiter is armed before `invalidate()`, and the callback latency is logged.
- `IDVMRZData.rawLines` — the DG1 MRZ exactly as stored, fillers intact (so apps don't
  reverse the display normalisation to build a stable identity hash).
- `IDVPassportData.faceImage` (`CGImage`) — the DG2 photo decoded without the extra JPEG
  re-encode that `faceImageData` carries. `faceImageData` is documented as JPEG quality `0.9`.
- `IDVPassportData.warnings` — non-fatal issues found while reading, in plain language.
- `IDVNFCConfiguration.strictMRZChecksums` (default `true`) — set `false` to accept a genuine
  chip whose DG1 carries a known check-digit error; the field is recorded in `warnings`
  (passive authentication still proves DG1 integrity).
- `IDVError.nfcUserCancelled` and `IDVError.nfcSessionTimeout` — distinct, user-friendly
  cases, so apps can suppress the alert when the user taps Cancel.

### Changed
- Chip Authentication advertised in an algorithm IDVKit does not implement yet (classic DH)
  now reports `.notPerformed` with a reason, **never `.failed`** — a genuine chip is never
  mislabeled as a forgery.
- Diagnostic logging (`IDVLog.isEnabled`): the passport number is no longer logged; one
  PII-free line is emitted per security step (secure channel / chip / active / passive auth).
- CoreNFC user-cancel now maps to `.nfcUserCancelled` and timeout to `.nfcSessionTimeout`
  (previously folded into `.cancelledByUser` / `.nfcSessionFailed`).

### Added — milestone work (previously unreleased)
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
