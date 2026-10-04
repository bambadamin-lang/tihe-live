# secure-core

The content protection core for TIHE Live. Everything secret happens here and nowhere else.

**Read [`../../docs/03-content-protection.md`](../../docs/03-content-protection.md) before
changing anything in this crate.** The design constraints are not obvious from the code alone.

## Why this is a separate Rust crate

Content keys must never enter the Dart heap, which is inspectable, and must never be written to
disk in plaintext. Putting all key handling in a native library compiled into the app — rather
than in the Flutter layer — is what makes that possible. It also means one implementation serves
Windows, Android and iOS instead of three.

## What it does

| Module | Responsibility |
|---|---|
| `crypto` | AES-128-CTR segment encryption, HKDF derivation, X25519 sealed boxes |
| `license` | Ed25519 licence verification, expiry and clock-rollback checks |
| `device` | Device fingerprint derivation and keypair handling |
| `container` | The `.tihex` offline container: read, write, verify |
| `keystore` | Platform key sealing (Android Keystore / Windows DPAPI), with a dev fallback |
| `loopback` | Local HLS server that decrypts segments in memory for the video engine |
| `ffi` | The surface Flutter calls through |

## Testing

```bash
cargo test                 # unit + round-trip tests
cargo clippy --all-targets -- -D warnings
```

The tests that matter most are the negative ones — a `.tihex` written for one device must fail
to open on another, a tampered licence must fail verification, and a rolled-back clock must be
caught. Those are the properties the product's protection rests on, so they are asserted
explicitly rather than assumed.

## CLI

```bash
cargo run --bin tihex -- inspect path/to/video.tihex
cargo run --bin tihex -- selftest
```

`inspect` prints a container's header without decrypting the payload, which is the first thing
you want when a download will not open. `selftest` runs the full crypto round trip and prints
what it verified — useful for confirming a cross-compiled build actually works on a device.
