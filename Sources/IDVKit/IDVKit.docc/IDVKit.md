# ``IDVKit``

Open-source, on-device identity verification for iOS — passport/eMRTD NFC,
MRZ scanning, face matching and liveness. No servers, no API keys, no networking.

## Overview

IDVKit reads a travel document end to end, entirely on the device:

1. **Scan the MRZ** — the machine-readable zone of a passport or ID card is read
   with the camera (Apple Vision) and parsed per ICAO Doc 9303 (TD1/TD2/TD3).
2. **Read the chip** — the derived key opens the eMRTD chip over NFC (PACE or
   BAC), reads the data groups, and runs passive and active authentication so a
   cloned or forged chip is rejected.
3. **Match the face** — an ArcFace/MobileFaceNet model compares a live, liveness-
   checked selfie against the document portrait.

Everything runs on-device. Nothing is uploaded, logged to disk, or sent to a
server — that privacy guarantee is the whole point.

Integrate the drop-in SwiftUI flow, or call the headless services directly.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:SupportedDocuments>
- <doc:ThemingAndBranding>

### Configuration

- ``IDVConfiguration``
- ``IDVVerificationStep``
- ``IDVMRZConfiguration``
- ``IDVNFCConfiguration``
- ``IDVFaceConfiguration``
- ``IDVUIConfiguration``

### Results

- ``IDVVerificationResult``
- ``IDVMRZData``
- ``IDVError``

### Diagnostics

- ``IDVLog``
