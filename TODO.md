# VerifID — Roadmap / TODO

Future work, deferred deliberately. The core pipeline (document scan → NFC chip
read → passive/active authentication → face match + liveness → result) is
complete and hardware-validated.

## Documents
- [ ] Document-type picker screen (currently the layout is auto-detected; some
      integrations want an explicit "Passport / ID card / Residence permit" step).
- [ ] Non-eMRTD documents: barcode-based IDs (e.g. US driver's licenses, PDF417)
      and photo-only documents without an NFC chip. Separate capture pipeline.

## Face
- [ ] **Model license provenance** — verify the bundled face-embedding model's
      training-data/weights license permits commercial redistribution, or swap it
      (e.g. OpenCV SFace, Apache-2.0) before making the repo public. See
      `Sources/VerifIDFace/Resources/README.md`.
- [ ] Match-threshold calibration guidance for integrators (config knob exists;
      default 0.65).

## Trust store
- [ ] Pakistan CSCA — obtain `CSCAPKI_PK` from DGIP (out-of-band; not publicly
      distributable) if PK chain-of-trust must go fully green. The SDK already
      reports the exact missing anchor.
- [ ] Optional: verify the master-list's own signer certificate (currently the
      member CSCAs are harvested without validating the list signature).

## Distribution
- [ ] Carthage + CocoaPods support via prebuilt `.xcframework`s attached to
      GitHub releases (SPM already supported).

## Localization
- [ ] Additional language translations (UI strings are already externalised to
      `Localizable.xcstrings`; only the base localization is filled in).

## Testing
- [ ] Automated UI / device tests for the ARKit liveness path (can't run in the
      simulator; needs a device lab or manual matrix).
