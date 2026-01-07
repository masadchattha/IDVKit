# VerifID — Architecture & Engineering Guide

This file is the **source of truth for how VerifID is built**. Read it before
making structural changes. It is auto-loaded by Claude Code and is written so a
new contributor (human or AI) can place any change in the right module and keep
the public API, privacy, and concurrency invariants intact.

VerifID is an open-source (MIT), 100%-on-device iOS identity-verification SDK:
MRZ scan → eMRTD NFC chip read (BAC/PACE + passive/active authentication) →
face match + liveness. No servers, no API keys, no networking, ever.

---

## 1. Module architecture (strict layering)

The package is a set of SwiftPM library products. **Dependencies point in one
direction only — downward.** A module may depend on anything strictly below it,
never sideways into a peer, never upward.

```
                         VerifID  (umbrella — @_exported re-exports everything)
                            │
                 ┌──────────┴───────────┐
                 │                      │
             VerifIDUI  ──────►  VerifIDMRZ · VerifIDNFC · VerifIDFace   (features)
                 │                      │
                 └──────────┬───────────┘
                            ▼
                       VerifIDCore   (models, config, errors, theme, logging, helpers)
                            ▲
        VerifIDJPEG2000 ────┘   (wraps COpenJPEG — vendored C, the only non-Swift target)
```

| Module | Owns | May depend on |
|---|---|---|
| **VerifIDCore** | `VIDConfiguration`, result models, `VIDError`, `VIDTheme`, `VIDLog`, shared `CGImage`/geometry helpers | (nothing internal) |
| **VerifIDJPEG2000** | Safe Swift wrapper over vendored OpenJPEG (`COpenJPEG`) for DG2 decode | Core, COpenJPEG |
| **VerifIDMRZ** | Vision OCR scanner + ICAO 9303 parser (TD1/TD2/TD3) | Core |
| **VerifIDNFC** | eMRTD: APDU, BAC/PACE, secure messaging, DG parsing, passive/active auth, CSCA trust store | Core, JPEG2000 |
| **VerifIDFace** | ArcFace/MobileFaceNet matching + liveness logic (`VIDLivenessSession`) | Core |
| **VerifIDUI** | Drop-in themeable SwiftUI flow + AR capture bridge | Core, MRZ, NFC, Face |
| **VerifID** | Umbrella facade; one-line integration; re-exports | all of the above |

**Rules for future edits**
- A change belongs in the **smallest / lowest module that fits**. Shared type
  needed by two features → it goes in Core, not copied.
- **Never introduce a sideways or upward dependency.** If VerifIDNFC needs
  something from VerifIDFace, the shared piece belongs in Core.
- The **only** C target is `COpenJPEG`. No other native/vendored code without a
  discussion — it breaks simulator builds and supply-chain review.
- Adding a new capability = usually a new feature module peer (Core-only deps) or
  an addition to an existing one. UI stays a thin layer over headless services.

Reference points (how top SDKs shaped this): Stripe-iOS and Firebase-iOS
(modular products, one concern per module, facade umbrella); Apple's
swift-crypto / swift-certificates (`package` access, spec test-vectors, DocC on
every public symbol); AndyQ/NFCPassportReader (the eMRTD baseline we replaced
with an in-house, CSCA-verifying implementation).

---

## 2. Public API surface — minimal and deliberate

The public API is a **product**, not a side effect. Treat every `public` symbol
as a support commitment.

- **Everything public carries the `VID` prefix.** If a symbol is not a documented
  integration point, it is `internal` (default) or `package` (needed across
  modules but not by app developers). Reach for `package` before `public`.
- **The integration contract is small:** `VIDConfiguration` (+ its nested config
  structs), `VIDVerificationFlowView` / the umbrella entry point, the result
  models (`VIDVerificationResult`, `VIDMRZData`, `VIDFaceMatchResult`, …),
  `VIDError`, `VIDTheme`, and `VIDLog`. That's the surface. Additions to it are a
  design decision, not a default.
- **Config over parameters.** New knobs are added as fields on the relevant
  nested config struct (`VIDMRZConfiguration`, `VIDNFCConfiguration`,
  `VIDFaceConfiguration`, `VIDUIConfiguration`) with a sensible default — never as
  a new positional argument that breaks call sites. Defaults must be the
  **safe** choice (e.g. passive authentication on, security details shown to the
  SDK but adjustable).
- **Views used only inside the drop-in flow stay internal.** Expose a screen as a
  standalone public component only when a developer genuinely needs to compose it
  themselves. Prefer configuring the flow over exposing its pieces.
- **DEBUG-only affordances** (e.g. the photo-picker reference override) live
  behind `#if DEBUG` **and** an explicit opt-in flag
  (`allowsDebugPhotoMatch`), so they can never ship in a release integration.
- Every public symbol gets **Apple-style DocC**: a summary line, then
  `- Parameters:` / `- Returns:` / `- Throws:` as applicable, plus a usage
  snippet on the primary entry points.

---

## 3. Non-negotiable invariants

These are correctness/trust properties. A change that weakens one is a bug, even
if it compiles and passes tests.

1. **No networking. No data collection.** Everything is on-device. A PR that adds
   a URLSession, analytics, or any egress is rejected. This is the product's
   entire differentiator.
2. **Never log sensitive data.** No biometric buffers, no document fields
   (name, number, DOB), no similarity scores. Logging is silent by default,
   gated behind `VIDLog.isEnabled`, and routed through
   `Logger.<category>.vidDebug/vidError`.
3. **Every failure is a typed `VIDError`.** Library code **never** calls
   `fatalError`, `try!`, or `fatalError`-adjacent traps on attacker-controlled
   input (malformed chips/images must throw, not crash).
4. **Security defaults stay strict.** Passive authentication (chain of trust via
   CSCA) is on by default. "Integrity-only" / relaxed modes are opt-in and
   clearly named. Chip-auth results are surfaced, never silently swallowed.
5. **Hardware paths are split from logic.** Anything touching NFC/ARKit/camera is
   thin; the testable logic (parsers, check digits, liveness state machine,
   crypto) is pure and unit-tested against spec vectors. See
   `VIDLivenessSession` (pure) vs `VIDLivenessARView` (hardware bridge).

---

## 4. Concurrency model (Swift 6, strict)

- The package builds under **Swift 6 strict concurrency**. Keep it warning-clean.
- Public value types are `Sendable`. Types that cross actor boundaries are
  `Sendable`; where a non-Sendable Apple type (e.g. `CGImage`,
  `VNFaceObservation`) forces it, the API is **synchronous** rather than faking
  `async` across a boundary (see `VIDFaceMatcher.match` — sync by design).
- UI and AR bridges are `@MainActor`. Per-frame ARKit work runs on a dedicated
  background `delegateQueue`, not the main thread (ARFrame retention lesson).
- Use `@unchecked Sendable` / `nonisolated(unsafe)` only with a comment
  explaining why it is actually safe (e.g. lock-guarded, single-writer).

---

## 5. Resources, models, testability

- Ship bundled assets (the CoreML face model, CSCA anchors) via
  `Bundle.module` — never a hardcoded `Bundle.main` name.
- **Bundled models must carry a clear, redistributable license** compatible with
  the SDK's own license. Record each model's source and license alongside it.
- Inject collaborators behind protocols where a test needs to stand in for
  hardware (passport reader, matcher). This is what lets NFC/face logic be tested
  in CI without a device.
- **Tests use spec vectors.** When a standard applies (ICAO 9303, BSI TR-03110/
  TR-03111), add the worked-example vectors from the spec rather than ad-hoc
  values. Every PR adds tests; CI runs build + test on the iOS simulator.

---

## 6. Tooling & CI

- **Formatting:** `swiftformat .` before pushing. Config is pinned in
  `.swiftformat` (philosophy: enforce consistency — indent, `self` removal,
  import order, whitespace — without reflowing hand-tuned crypto/OID layout).
  CI runs `swiftformat --lint` and it is a required check.
- **CI Xcode:** the workflow selects the newest installed **Xcode 16.x**, because
  `swift-certificates` ≥ 1.19.3 needs Swift tools 6.1 (Xcode 16.3+). Don't pin
  back to the default `Xcode_16.app` symlink — it's 16.0 and fails dependency
  resolution.
- **Conventional Commits** (`feat(scope):`, `fix(scope):`, `test:`, `docs:`,
  `chore:`, `refactor:`). Keep commits small and focused.
- Branch protection + PR template + CODEOWNERS live in `.github/`.

---

## 7. Where does my change go? (quick decision guide)

- New **result field / config knob** → VerifIDCore (models/config), with a default.
- New **MRZ document format / parser rule** → VerifIDMRZ.
- New **chip protocol / crypto / trust-store logic** → VerifIDNFC (+ spec vectors).
- New **matching / liveness rule** → VerifIDFace (pure logic in `VIDLivenessSession`).
- New **screen / theming / flow step** → VerifIDUI (thin; logic stays in features).
- Shared by two features → VerifIDCore.
- New third-party/native dependency → **stop and discuss** (supply-chain + sim builds).

## 8. Constants & design tokens (no magic numbers, no inline copy)

View bodies contain **no raw numbers, no hardcoded display strings, and no
SF-Symbol string literals.** Everything is extracted into three `internal`
namespaces per UI module (see `VerifIDUI/VIDLayout.swift`, `VIDStrings.swift`,
`VIDIcon.swift`):

- **`VIDLayout`** — fixed metrics (element sizes, glyph/animation dimensions,
  stroke widths, opacities, durations, arc angles), grouped into sub-enums
  (`Spacing`, `Size`, `IconSize`, `Radius`, `Stroke`, `Opacity`, `Duration`),
  each token carrying a `/// value` doc comment.
- **`VIDStrings`** — all display copy as `LocalizedStringKey` constants, grouped
  by screen. The flow stays localizable (the constant's value is the
  `Localizable.xcstrings` key). Dynamic/interpolated copy is a `static func`
  returning `String` (rendered with `Text(verbatim:)`). Because
  `LocalizedStringKey` isn't `Sendable`, these constants are
  `nonisolated(unsafe)` (compile-time literals, never mutated — safe).
- **`VIDIcon`** — every SF-Symbol name, grouped (`Document`, `Challenge`, …).
- **`VIDColor`** — the few **fixed, non-themeable** colours (the Face-ID-style
  green/gray ring ticks, the decorative glow palette). These are deliberately
  system values rather than theme tokens so the capture matches the reference,
  and they are picked to hold contrast on **both** the light and dark capture
  backgrounds. Anything an integrator should be able to restyle belongs on
  `VIDTheme`, not here — keep this namespace small.

Rules:
- **Themeable vs fixed.** Anything an integrator should be able to restyle
  (colors, fonts, `screenPadding`, `cornerRadius`, `buttonCornerRadius`) stays on
  **`VIDTheme`** — never duplicate it into `VIDLayout`. `VIDLayout` is only for
  fixed, non-themeable metrics.
- **`internal`, never `public`.** These are implementation details, not API. This
  is the key SDK-vs-app difference: an app can globalize constants freely; an SDK
  must not leak them into its public surface.
- **Constants live in the module that uses them.** They can't cross the one-way
  dependency graph — e.g. `VerifIDMRZ` (a lower module) cannot use `VerifIDUI`'s
  constants; it needs its own, or shared value types promoted to `VerifIDCore`.
- **Spec/domain constants are exempt.** Crypto values (ASN.1 OIDs, EC curve
  parameters, ICAO check-digit weights, MRZ field offsets) stay as named
  constants in their feature module — they're the spec, not UI magic numbers.
- Idioms: `.zero` instead of `0`; always explicit stack spacing
  (`VStack(spacing:)`); logging only through `Logger.<category>.vidDebug/vidError`
  gated by `VIDLog.isEnabled` — never `print`.

When in doubt: smallest module, lowest layer, narrowest access modifier, safest
default, a typed error, a spec-backed test, and nothing that touches the network.
