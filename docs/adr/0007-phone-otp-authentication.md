# ADR-0007 — Phone + SMS OTP authentication

**Status:** Accepted · 2026-09-27

## Context

Students in Iran expect phone-number sign-in. We also need a strong identity anchor: device
binding and watermarking are only as meaningful as the identity behind them.

## Decision

Phone number + SMS OTP as the only student sign-in method. No passwords. SMS behind a
`SmsProvider` interface — console driver in development, Kavenegar/SMS.ir in production.

## Consequences

**Good.** Familiar to users, no password reset flows, no credential stuffing, no password
storage risk. The phone number is a real-world identity that makes watermarks meaningful and
account sharing personally costly.

**Bad.** Per-message SMS cost and a dependency on provider uptime. Sign-in fails where there
is no signal. SIM-swap becomes the account takeover path. Number changes need a support flow.

**Mitigations.** Rate limits per phone and per IP on `otp_codes`. The OTP request endpoint
returns an identical response whether or not the number exists, so it cannot enumerate users.
Long-lived rotating refresh tokens mean students rarely re-authenticate, which keeps SMS
volume — and cost — low. The provider interface means a second provider can be added as a
failover without touching auth logic.
