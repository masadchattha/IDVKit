# VerifID

**Open-source identity verification for iOS. Passport NFC + MRZ scan + face match + liveness — 100% on-device.**

No API keys. No server. No SDK fees. Nothing leaves the phone.

> ⚠️ **Status: pre-release (`0.1.0-dev`).** The full pipeline — document scan, NFC chip read, passive + active authentication, and face match + liveness — is implemented and validated on device. Before shipping in a **commercial, public** product, confirm the bundled face-embedding model's license (see [`Sources/VerifIDFace/Resources/README.md`](Sources/VerifIDFace/Resources/README.md)).

## Why VerifID

Commercial identity-verification SDKs (Persona, Onfido, Veriff) charge per verification and upload your user's passport and face to their cloud. VerifID does the same job entirely on the device — and you can read every line of code that touches the data.

| | Commercial IDV SDKs | **VerifID** |
|---|---|---|
| Price | ~$1–3 per verification | Free (MIT) |
| Documents & biometrics | Uploaded to vendor cloud | **Never leave the device** |
| API keys / accounts | Required | None |
| Code | Closed | Open — audit it yourself |

**Features**

- 🛂 **NFC passport reading (eMRTD / ICAO 9303) — from scratch, no third-party NFC library** — BER-TLV, ISO 7816-4 APDUs, DG1/DG2/SOD parsing, and **both access protocols**:
  - **BAC** (3DES) — validated byte-for-byte against the ICAO Doc 9303 **Appendix D** worked example
  - **PACE** (ECDH Generic Mapping, AES) — including hand-written brainpool/NIST elliptic-curve math (Apple's crypto can't do brainpool), validated end-to-end against the **Appendix G** worked example
  - `.automatic` access mode prefers PACE and falls back to BAC
- ✅ **Passive authentication, split honestly** — VerifID verifies **data integrity** (every data-group hash matches the SOD, and the SOD signature is valid) with no trust store needed, and **chain of trust** (the Document Signer Certificate chains to a CSCA you supply). The two are reported separately (`dataIntegrity` / `chainOfTrust`) so an app without a CSCA store still learns whether the data is intact — instead of a misleading pass/fail. Built on Apple's `swift-certificates`/`swift-asn1`, no networking.
- 🪪 **Multiple document types** — passport (TD3), ID card and residence permit (TD1/TD2). The MRZ layout is auto-detected; the same chip pipeline reads all eMRTDs.
- 🔍 **MRZ camera scan** — Apple Vision OCR, ICAO 9303 check-digit validation on every frame, no Tesseract
- 🖼 **JPEG2000 decoding** — OpenJPEG 2.5.4 compiled from vendored source; device, simulator and Catalyst
- 🛡 **Active / Chip Authentication (anti-clone)** — proves the physical chip is the original, not a copy (RSA ISO 9796-2 recovery + brainpool/NIST ECDSA)
- 🙂 **Face match** — MobileFaceNet CoreML, ArcFace 5-point alignment, cosine similarity with a configurable threshold, returning the score (never a bare pass/fail)
- 👁 **Active liveness** — ARKit blend-shape challenges (blink / smile / open mouth / head turn), micro-movement anti-spoofing, and multiple-face rejection
- 🎨 **Drop-in SwiftUI flow** — themeable (`VIDTheme`), brandable with your app icon and name (`VIDBrandingConfiguration`), customizable Apple NFC sheet text — or go fully headless
- 🔒 **Zero networking code in the package** — grep it; the privacy promise is auditable

## Installation

### Swift Package Manager (recommended)

In Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/masadchattha/verifid-ios
```

Or in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/masadchattha/verifid-ios", from: "0.1.0")
]
```

Pick your products — the umbrella, or à la carte:

| Product | What you get |
|---|---|
| `VerifID` | Everything, one import |
| `VerifIDUI` | Drop-in customizable UI flow |
| `VerifIDMRZ` | MRZ scanner + ICAO 9303 parser (headless or with `VIDMRZScannerView`) |
| `VerifIDNFC` | Passport chip reading (headless) |
| `VerifIDFace` | Liveness + face matching (headless) |
| `VerifIDJPEG2000` | Just the JPEG2000 decoder |

### Carthage

Prebuilt `VerifID.xcframework` bundles will be attached to GitHub releases from `0.1.0`; add the release-asset binary reference to your `Cartfile`. Until then, SPM is the supported path.

## Quick start

### Drop-in flow (SwiftUI)

```swift
import VerifID

.sheet(isPresented: $showVerification) {
    VIDVerificationFlowView { result in
        if case .verified(let outcome) = result {
            print(outcome.document.mrz.surname, outcome.faceMatch?.similarity)
        }
    }
    .vidTheme(MyBrandTheme())   // optional — colors, fonts, shape
}
```

### What you get back

`VIDVerificationResult` is `.verified(VIDVerificationOutcome)`, `.failed(VIDError)`,
or `.cancelled`. The outcome carries everything, on-device:

```swift
outcome.document.mrz              // VIDMRZData — name, doc number, DOB, expiry, nationality…
outcome.document.faceImageData    // the chip portrait (DG2), JPEG
outcome.document.dataGroupsRead   // which data groups were read
outcome.document.authenticity     // VIDChipAuthenticityResult:
//   .passiveAuthentication.dataIntegrity   — hashes + SOD signature valid
//   .passiveAuthentication.chainOfTrust    — DSC chains to a trusted CSCA
//   .activeAuthentication                  — chip is genuine (anti-clone)
outcome.liveness                  // VIDLivenessOutcome? — challenges passed
outcome.faceMatch                 // VIDFaceMatchResult? — isMatch, similarity, both images
```

Every status is an explicit `.passed / .failed(reason:) / .notPerformed(reason:) /
.notSupportedByChip` — never a silent boolean.

Brand it as yours:

```swift
var config = VIDConfiguration.default
config.ui.branding = VIDBrandingConfiguration(
    logoImageData: UIImage(named: "AppIcon")?.pngData(),
    appName: "Acme"
)
```

Let the user pick a document type before scanning (a picker screen appears
automatically when you allow two or more kinds; with one kind it's skipped):

```swift
var config = VIDConfiguration.default
config.mrz.allowedDocuments = [.passport, .idCard, .residencePermit]
```

### Headless — MRZ scanning today

```swift
import VerifIDMRZ

VIDMRZScannerView { mrz in
    print(mrz.documentNumber, mrz.surname)   // checksum-valid, guaranteed
} onError: { error in ... }
```

Or drive the scanner with your own UI via `VIDMRZScanner` (`previewLayer`, `onResult`, `toggleTorch()`).

### Headless — decode a DG2 JPEG2000 face image today

```swift
import VerifIDJPEG2000

let cgImage = try VIDJPEG2000Decoder.decode(dg2ImageData)   // throws, never crashes
```

### Logging

Silent by default. Opt in during development:

```swift
VIDLog.isEnabled = true   // unified logging, subsystem "dev.verifid"
```

Biometric data, document fields and similarity scores are never logged.

## Passport chip authenticity (passive authentication)

Supply your own CSCA trust anchors to get the full chain-of-trust check:

```swift
let store = try VIDTrustStore(pemFileURL: myCSCABundleURL)   // or VIDTrustStore(pem:) / (certificatesDER:)
var config = VIDConfiguration.default
config.nfc.passiveAuthentication = .enabled(cscaTrustStore: store)

let passport = try await VIDPassportReader(configuration: config.nfc).read(mrzKey: key)
let pa = passport.authenticity.passiveAuthentication
pa.dataIntegrity    // hashes match + SOD signature valid (no trust store needed)
pa.chainOfTrust     // DSC chains to a trusted CSCA (needs the store)
pa.isFullyVerified  // both passed
```

CSCA certificates are public government credentials. VerifID does **not** bundle a
master list — ICAO's trust model expects you to establish CSCA trust yourself, and
a frozen snapshot silently rejects newer passports. Get an up-to-date list from the
[ICAO PKD](https://download.pkd.icao.int) or the German BSI master list, and refresh it periodically.

### Known limitations (being honest)

- **Passive authentication proves data authenticity, not that *this* chip is the original** — a clone passes it. Clone detection is **Active / Chip Authentication**, which VerifID implements (`authenticity.activeAuthentication`); check it, not just passive auth, when clone resistance matters.
- **RSA-PSS** Document Signer Certificates *are* verified (via `_CryptoExtras`), for the standard profile (MGF1 hash = signature hash, salt = digest length). A non-standard PSS salt length or MGF1 hash is reported honestly as unverified. **ECDSA-SHA1** DSCs are not yet verifiable.
- **Brainpool elliptic curves** are supported for **PACE** (hand-written EC math), but a DSC with a brainpool *public key* is not verifiable for passive auth (Apple crypto limitation); documented gap.
- **No CRL/revocation checking** — typical for mobile readers; stated per ICAO's requirement.

## Host-app requirements

**Requires iOS 18+** (the bundled face-embedding CoreML model targets iOS 18). A
Swift package cannot declare entitlements — your app must add:

1. **Capability:** Near Field Communication Tag Reading
2. **Entitlement:** `com.apple.developer.nfc.readersession.formats` = `["TAG"]`
3. **Info.plist:**
   - `com.apple.developer.nfc.readersession.iso7816.select-identifiers` = `["A0000002471001", "A0000002472001", "00000000000000"]`
   - `NFCReaderUsageDescription`
   - `NSCameraUsageDescription` (also covers the face-scan camera)

NFC and the ARKit face scan need a physical device; `VIDMockPassportReader` covers
the simulator for the chip path. Face tracking works on any A12-or-newer device
(all iOS 18 devices) — TrueDepth is not required. See `Examples/VerifIDExample` for
a complete, runnable integration.

## API conventions

- All public types carry the `VID` prefix (`VIDPassportReader`, `VIDMRZScannerView`, `VIDError`, …) so nothing ever collides with your code or Apple frameworks.
- Everything not meant for integrators is `internal`/`package` — the public surface is the contract, and it follows SemVer.
- Every failure is a typed `VIDError`; the SDK never calls `fatalError`.
- Swift 6, strict concurrency, async/await, iOS 18+.

## License

MIT — see [LICENSE](LICENSE). Vendored OpenJPEG is BSD-2-Clause (`Sources/COpenJPEG/LICENSE`). Attributions in [NOTICE](NOTICE).
