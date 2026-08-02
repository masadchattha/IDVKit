# Security Policy

IDVKit is security-sensitive software (identity documents, biometrics).

## Reporting a vulnerability
Please use GitHub's private vulnerability reporting ("Report a vulnerability"
under the Security tab) instead of a public issue. You will get a response
within 72 hours. Coordinated disclosure is credited in release notes.

## Design guarantees
- No networking code exists anywhere in this package; data never leaves the device.
- Passive authentication (chip genuineness) is enabled by default.
- Logging is off by default and never includes biometric or document data.
