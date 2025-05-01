# Contributing to VerifID

Thanks for helping build open, private identity verification for iOS.

- Look for `good first issue` labels; open a Discussion before large changes.
- Every PR needs tests (spec test vectors where a standard applies — ICAO 9303,
  BSI TR-03110) and must pass CI (build + tests on the iOS simulator).
- Security-sensitive code (crypto, chip auth, liveness) gets extra review time.
  Never weaken a default (e.g. passive authentication stays ON by default).
- Found a vulnerability? See SECURITY.md — do not open a public issue.
