# README assets — replacement checklist

These are **labeled placeholders** so the README layout is visible now. Replace each
file *in place* (keep the same filename) with the real asset and the README updates
itself. **Golden rule: never use an AI-generated human face anywhere — we're a
face-match product.** AI is fine ONLY for the abstract hero backdrop.

| File | What it should become | Size | Source |
|---|---|---|---|
| `hero-banner.png` | "IDVKit" wordmark + tagline over an abstract dark chip/MRZ backdrop | 1280×640 | AI backdrop **only**; set the text yourself in Figma. Doubles as the GitHub **Social preview** (Settings → Social preview). PNG < 1MB, keep text center-safe. |
| `demo-full-flow.gif` | Real iPhone screen recording of the whole flow: MRZ scan → NFC "hold near chip" sheet → green "chip authentic" → face + liveness → "Verified" | ~800px wide, < 5MB, loops, ~10–15s | **Real device recording** (NFC needs hardware). This is the single most important asset. |
| `shot-mrz.png` | Real screenshot — MRZ scanner reticle over a document | iPhone ratio (~390 wide), device-framed | Real screenshot |
| `shot-nfc.png` | Real screenshot — the CoreNFC "hold near passport" sheet + tap animation | same | Real screenshot |
| `shot-authentic.png` | Real screenshot — result screen with name + green authenticity checks | same | Real screenshot |
| `shot-face.png` | Real screenshot — Face-ID-style liveness capture mid-challenge | same | Real screenshot |
| `video-poster.png` | Thumbnail with a ▶ play glyph; the README links it to the walkthrough | 1280×720 | Screenshot + play button. Update the link in README ("See it in action") to the real YouTube/Loom URL. |

## Also (not in the README, for later)
- **Logo mark** (square, 512×512 PNG + SVG) — for favicon, DocC, pinned-repo thumbnail.
- **US passport onboarding illustration** — Wikimedia `File:United States Passport.svg` (public domain, US federal work). For the sample app, not the README.
- **eMRTD chip symbol** — Wikimedia `File:EPassport logo.svg` (verify its file-page license before shipping).

## Notes
- GitHub does **not** reliably embed `.mp4` in a README — use the GIF for the inline demo and link the full video via the poster.
- The architecture diagram is inline **Mermaid** in the README (version-controlled) — no image file needed.
