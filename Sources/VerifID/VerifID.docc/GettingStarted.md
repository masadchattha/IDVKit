# Getting Started

Add the drop-in flow to your app and read your first document.

## Requirements

- iOS 18+, Xcode 16.3+.
- A physical device — NFC and the ARKit face scan do not run in the simulator.
- Host-app entitlements and Info.plist keys (the package can't add these for you):
  - `com.apple.developer.nfc.readersession.formats` = `["TAG"]`
  - Info.plist `com.apple.developer.nfc.readersession.iso7816.select-identifiers`
    = `["A0000002471001", "A0000002472001"]`
  - `NFCReaderUsageDescription`, `NSCameraUsageDescription`

## The drop-in flow

Present ``VIDVerificationFlowView`` and handle the result. That's the whole
integration:

```swift
import SwiftUI
import VerifID

struct VerifyButton: View {
    @State private var verifying = false

    var body: some View {
        Button("Verify identity") { verifying = true }
            .sheet(isPresented: $verifying) {
                VIDVerificationFlowView { result in
                    verifying = false
                    if case let .verified(outcome) = result {
                        print(outcome.document.mrz.surname)
                    }
                }
            }
    }
}
```

## Offering a document choice

By default the scanner auto-detects the document layout. To let the user pick a
type first, list two or more kinds — a selection screen appears automatically:

```swift
var config = VIDConfiguration.default
config.mrz.allowedDocuments = [.passport, .idCard, .residencePermit]

VIDVerificationFlowView(configuration: config) { result in
    // …
}
```

With a single kind (or the default `[.any]`) the picker is skipped.

## Chip authenticity

Passive authentication verifies the chip's data integrity out of the box. To also
verify the document signer chains to a trusted country (CSCA), supply a trust
store — see ``VIDNFCConfiguration/PassiveAuthentication``.

## Going headless

Every stage is usable without the UI. For example, scan an MRZ with
``VIDMRZScannerView``, or read a chip directly with `VIDPassportReader`. The
drop-in flow is just a thin, themeable layer over these services.
