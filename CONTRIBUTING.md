# Contributing to IDVKit

Thanks for helping build open, private identity verification for iOS. This guide
covers how to set up, the bar every change must clear, and how PRs are reviewed.

## Getting started

- **Requirements:** macOS with Xcode 16.3+ (needed for Swift tools 6.1, which
  `swift-certificates` depends on), an iOS 18 simulator. NFC and the ARKit
  face scan need a physical device (the simulator can't do either); use
  `IDVMockPassportReader` for the chip path in the simulator.
- **Clone & open:** `git clone https://github.com/masadchattha/IDVKit`, then
  open the package in Xcode or build from the CLI.
- **Build:** `xcodebuild build -scheme IDVKit -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- **Test:** `xcodebuild test -scheme IDVKit-Package -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- **Example app:** `Examples/IDVKitExample` — run it on a device to exercise NFC + face.

## Project layout

The package is modular; keep changes in the smallest module that fits:

| Module | Responsibility |
|---|---|
| `IDVKitCore` | Config, result models, errors, theming, logging, shared helpers |
| `IDVKitMRZ` | MRZ camera scanner + ICAO 9303 parser |
| `IDVKitNFC` | eMRTD chip reading, BAC/PACE, passive/active authentication |
| `IDVKitJPEG2000` | JPEG2000 decoder (vendored OpenJPEG) |
| `IDVKitFace` | Face matching + liveness logic |
| `IDVKitUI` | Drop-in SwiftUI screens |
| `IDVKit` | Umbrella that re-exports everything |

## Coding conventions

- **Public API** carries the `IDV` prefix and is a deliberate, minimal surface.
  Anything that isn't a documented integration point is `internal`/`package`.
- **Document every public symbol** with Apple-style DocC (`///`, with
  `- Parameters/Returns/Throws`).
- **No networking, ever.** IDVKit is 100% on-device — a PR that adds a network
  call or data collection will not be merged.
- **Every failure is a typed `IDVError`.** Never call `fatalError` in library code.
- **Logging** goes through `Logger.<category>.idvDebug/idvError` (gated by
  `IDVLog.isEnabled`). Never log biometric data, document fields, or scores.
- **Formatting:** run `swiftformat .` before pushing (CI enforces `--lint`).
- Swift 6, strict concurrency, async/await.

## Tests

- **Every PR needs tests.** Where a standard applies (ICAO 9303, BSI TR-03110),
  add the spec's worked-example vectors rather than ad-hoc values.
- Tests must pass in CI (build + test on the iOS simulator).
- Camera/NFC/ARKit paths that can't run in CI should be split so their logic is
  unit-testable without the hardware (see `IDVLivenessSession`).

## Commits & pull requests

- Use **Conventional Commits**: `feat(scope): …`, `fix(scope): …`, `test:`,
  `docs:`, `chore:`, `refactor:`.
- Keep PRs focused and small. Fill in the PR template checklist.
- **Merge bar:** CI green + at least one approving review. Security-sensitive code
  (crypto, chip auth, liveness) gets extra review time, and **defaults are never
  weakened** (e.g. passive authentication stays on by default).
- Open a Discussion before large or API-changing work; look for `good first issue`.

## Security

Found a vulnerability? **Do not open a public issue** — follow `SECURITY.md`.
