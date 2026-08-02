# Supported Documents

Which identity documents IDVKit reads, and how the document-type choice behaves.

## Overview

IDVKit reads **eMRTDs** — electronic machine-readable travel documents that
carry a contactless chip conforming to ICAO Doc 9303. In practice that means:

| Document | MRZ format | Chip | Notes |
|---|---|---|---|
| Passport | TD3 (2 × 44) | Yes | The classic booklet photo page. |
| National ID card | TD1 (3 × 30), sometimes TD2 | Usually | EU cards issued since Aug 2021 (Reg. (EU) 2019/1157) are chipped. |
| Residence permit | TD1 (3 × 30) | Yes | EU permits per Reg. (EC) 1030/2002. |

All three are read the **same way**: the MRZ yields the chip-access key, and the
same NFC application (ICAO eMRTD applet, AID `A0000002471001`) is selected on the
chip regardless of document kind. There is no per-document application to switch.

## Do EU ID cards and residence permits have an MRZ?

Yes. Modern EU national ID cards and residence permits are ID-1 (credit-card)
size with a three-line **TD1** machine-readable zone on the back and a contactless
chip — the same family of standards as passports. IDVKit parses TD1 and TD2 in
addition to the passport's TD3.

## The document type is detected, not trusted

The user's pick is never treated as ground truth. After a scan, the **MRZ itself**
decides the document type (per ICAO Doc 9303), via ``IDVMRZData/detectedDocumentKind``:

- the **layout** — TD3 is a passport; TD1 / TD2 are cards, and
- the **document code** — a code beginning with `P` is a passport.

The picker (see ``IDVMRZConfiguration/allowedDocuments``) then serves two roles:

- **Guidance** — it shapes the on-screen guide box and, when only one type is
  allowed, skips the selection screen entirely.
- **Acceptance** — the flow enforces `allowedDocuments` against the *detected*
  type. A document whose detected type isn't in the allowed set is rejected with
  a clear message rather than read; if it is allowed but differs from what the
  user tapped, the mismatch is surfaced so they can continue or re-pick.

Passport-vs-card detection is reliable. An **ID card and a residence permit share
the TD1 layout and cannot be told apart from the MRZ alone** (their codes are
issuer-defined, not standardised by ICAO), so both are treated as the same
category — a card presented under either is accepted.

## Recognition and validation

Every MRZ is validated before it is accepted: the check digits (document number,
date of birth, expiry) and the composite check must all pass, so a single OCR
error is rejected rather than carried into the chip-access key. Use
``IDVMRZData/matches(_:)`` to check a scanned MRZ against a document kind yourself.
