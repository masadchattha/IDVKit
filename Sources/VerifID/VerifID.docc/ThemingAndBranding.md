# Theming & Branding

Make the drop-in flow feel native to your app — colors, fonts, logo, and
optional custom artwork.

## Overview

The flow ships with a calm default look and adapts to your brand three ways:
**theme** (colors, corner radius, fonts), **branding** (logo and product name),
and **illustrations** (optional hero artwork). Every hero screen falls back to a
theme-tinted SF Symbol, so the flow looks finished with zero custom assets.

## Theme

Provide a ``VIDTheme`` to recolor everything and apply it with `.vidTheme(_:)`:

```swift
VIDVerificationFlowView { result in /* … */ }
    .vidTheme(MyTheme())
```

A theme defines the palette (`background`, `surface`, `primary`, `onPrimary`,
`textPrimary`, `textSecondary`, `warning`), geometry (`cornerRadius`,
`buttonCornerRadius`, `screenPadding`), and a `font(_:)` for each text role. The
built-in ``VIDDefaultTheme`` is a good starting point.

## Branding

Set your logo and product name through ``VIDBrandingConfiguration``:

```swift
var config = VIDConfiguration.default
config.ui.branding = VIDBrandingConfiguration(
    logoImageData: UIImage(named: "AppIcon")?.pngData(),
    appName: "Acme"
)
```

The logo appears on the intro screen; leaving it `nil` shows a themed hero symbol
instead. `showsPoweredByBadge` toggles the subtle on-device footer.

## Illustrations

Replace the default hero symbols with your own art via ``VIDIllustrations``. Each
slot is optional — set one or all:

```swift
config.ui.illustrations = VIDIllustrations(
    intro: UIImage(named: "verify-hero")?.pngData(),
    chipGuidance: UIImage(named: "chip-tap")?.pngData(),
    faceIntro: UIImage(named: "face-scan")?.pngData()
)
```

Use a **square, transparent-background PNG around 240×240 pt (720 px @3x)**. Keep
artwork on a single accent (or neutral) so it recolors gracefully when a host
changes the theme; anything left `nil` keeps the theme-tinted SF Symbol.

## Copy & localization

All on-screen text lives in the module's `Localizable.xcstrings`, so you can
override strings and add languages through the standard String Catalog mechanism.
