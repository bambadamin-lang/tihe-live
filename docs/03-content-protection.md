# Content Protection Design

> Read [08-threat-model.md](08-threat-model.md) alongside this. This file describes *what we
> build*; the threat model describes *what it actually stops*.

## Principles

1. **No secret in Dart.** The Dart heap is inspectable. Every key, every signature check,
   every decryption happens in `packages/secure-core` (Rust).
2. **Keys are per-video and per-device.** One extracted key compromises one video on one
   device, never the library.
3. **Everything is revocable.** Any license can be killed server-side without re-encrypting
   or re-uploading a single byte of video.
4. **Assume eventual failure, guarantee attribution.** Every frame a student sees carries
   their identity. When content leaks, we know whose account it came from.
5. **Swappable.** Every operation below sits behind a `ContentProtectionProvider` trait so
   Widevine/PlayReady/FairPlay can be added in M7 as a second implementation.

## Key hierarchy

```
  KEK (Key Encryption Key)          — 256-bit, API environment / Vault. Never leaves the server.
   └── CEK (Content Encryption Key) — 128-bit, one per video, AES-CTR. Stored wrapped in Postgres.
        └── DWK (Device-Wrapped Key) — CEK re-wrapped for one device's X25519 public key.
                                       Minted per playback session or per download.

  LSK (License Signing Key)         — Ed25519 private, API only. Public key embedded in the app.
  DIK (Device Identity Key)         — X25519 keypair generated on device, private key sealed
                                       in Android Keystore / Windows DPAPI. Never exported.
```

Rotating a CEK means re-encrypting one video. Rotating the KEK means re-wrapping rows in
`content_keys`, no video touched. Rotating the LSK invalidates outstanding licenses by
design — that is the emergency lever.

## Layer 1 — Transport

- TLS everywhere. The app pins the server's certificate (SPKI pin, with a backup pin so
  certificate renewal does not brick installed apps).
- Every request carries a short-lived JWT access token (15 min) bound to a device id. The
  refresh token (30 days) is single-use and rotating; reuse of a consumed refresh token
  revokes the whole device session and is logged as a theft signal.
- Media segment requests additionally carry a playback-session token with a 2-minute TTL,
  scoped to one video and one device.

## Layer 2 — At rest in MinIO

- Both buckets (`tihe-raw`, `tihe-vod`) are private. No anonymous read policy, ever.
- Segments are stored **already encrypted** with the video's CEK (AES-128-CTR). MinIO's own
  server-side encryption is not relied upon — a stolen MinIO credential yields ciphertext.
- Access is by presigned URL only, minted per playback session, 2-minute expiry, and the
  presign is generated only after enrollment and license checks pass.
- Raw egress output in `tihe-raw` is deleted after successful packaging (configurable
  retention, default 7 days) so an unencrypted master copy does not sit around.

## Layer 3 — Online playback

1. Client: `POST /playback/{videoId}/session` with `deviceId`.
2. Server checks, in order: token valid → device registered and not revoked → enrollment
   active → license valid and not expired → concurrent-stream limit not exceeded.
3. Server unwraps the CEK with the KEK, re-wraps it as a DWK for the device's X25519 public
   key (sealed box), and returns:

```jsonc
{
  "sessionId": "ps_01J...",
  "manifestUrl": "https://minio.tihe.local/tihe-vod/v_01J.../master.m3u8?X-Amz-...",
  "segmentBaseUrl": "https://minio.tihe.local/tihe-vod/v_01J.../",
  "wrappedKey": "base64(sealed_box(CEK, devicePubKey))",
  "keyId": "ck_01J...",
  "encryption": { "scheme": "AES-128-CTR", "ivMode": "per-segment-sequence" },
  "watermark": {
    "text": "علی کریمی\n09121234567",
    "opacity": 0.28, "fontSize": 13,
    "movement": "corners", "periodSeconds": 27, "seed": 918273
  },
  "expiresAt": "2026-09-27T11:42:00Z",
  "heartbeatIntervalSeconds": 30
}
```

4. Dart passes this to Rust. Rust opens the sealed box using the device private key, holds
   the CEK in `mlock`ed memory, and starts the loopback server.
5. The video engine plays `http://127.0.0.1:{port}/{sessionToken}/master.m3u8`. Rust fetches
   encrypted segments from MinIO, decrypts in memory, serves plaintext to loopback.
6. On pause/stop/background, the CEK is zeroed. Resuming re-derives it from the wrapped key
   still held for the session; an expired session re-requests from the server.

## Layer 4 — Offline: the `.tihex` container

```
┌──────────────────────────────────────────────────────────────┐
│ MAGIC "TIHEX\x00" (6 B) │ VERSION u16 │ HEADER_LEN u32        │
├──────────────────────────────────────────────────────────────┤
│ HEADER (CBOR, HEADER_LEN bytes)                              │
│   videoId, title, durationMs, createdAt                      │
│   renditions[]: { id, width, height, bitrate, segmentCount }  │
│   segmentIndex[]: { rendition, seq, offset, len, iv }         │
│   wrappedKey: sealed_box(CEK, devicePubKey)                   │
│   licenseId, deviceId, notAfter, revocationEpoch             │
│   attachments[]: { id, name, mime, offset, len }              │
├──────────────────────────────────────────────────────────────┤
│ SIGNATURE Ed25519 over HEADER (64 B)                         │
├──────────────────────────────────────────────────────────────┤
│ PAYLOAD: encrypted segments, contiguous, in index order       │
└──────────────────────────────────────────────────────────────┘
```

Properties that matter:

- The header is **signed**, so a student cannot extend `notAfter` or swap in another
  device's id. Tampering fails verification and the file refuses to open.
- `wrappedKey` is sealed to **that device's** public key, whose private half never leaves the
  OS keystore. Copying `.tihex` to a friend's machine produces an unopenable file — not a
  file that plays with a warning, an unopenable one.
- The segment index allows seeking and partial downloads: the file is valid and playable up
  to the last complete segment, which is what makes "download and watch simultaneously"
  work.
- Attachments (PDF/HTML) ride inside the same encrypted container, so course materials are
  protected the same way the video is.

Files live in the app's private storage (`getApplicationSupportDirectory()`), not in
Downloads or on external storage.

## Layer 5 — Licenses

An Ed25519-signed CBOR blob, verified **offline** by the app against a public key baked into
the binary:

```jsonc
{
  "v": 1,
  "licenseId": "lic_01J...",
  "userId": "usr_01J...",
  "deviceIds": ["dev_01J...", "dev_01K..."],
  "scope": { "courseIds": ["crs_01J..."], "videoIds": [] },
  "notBefore": "2026-09-27T00:00:00Z",
  "notAfter":  "2026-10-27T00:00:00Z",
  "maxDevices": 2,
  "maxConcurrentStreams": 1,
  "offlineWindowDays": 30,
  "revocationEpoch": 7,
  "issuedAt": "2026-09-27T11:10:00Z",
  "serverTime": "2026-09-27T11:10:00Z"
}
```

**Clock rollback defence.** A device that is offline cannot be trusted about the time. Three
mechanisms together:

1. A monotonic counter in the keystore, incremented on every license check. It never
   decreases, so setting the clock back is detectable.
2. `serverTime` from the last successful online contact is stored sealed. If the system clock
   reads *earlier* than the stored `serverTime`, the device is lying and playback stops.
3. A cumulative offline-play-time counter. Even with a frozen clock, the licence exhausts.

**Revocation.** `revocationEpoch` is a per-user integer that increments when an admin revokes.
On heartbeat (every 30 s online) the server returns its current epoch; a device holding a
lower epoch discards its licence and its cached keys immediately. Offline devices honour it
at their next contact, bounded by `offlineWindowDays`.

## Layer 6 — Watermarking

**Phase 1 — visible overlay, always on.** Rendered in the native view layer above the video
surface, not as a Dart widget, so patching the Dart UI does not remove it:

- Content: the viewer's name with their full phone number beneath it, and nothing else
  (e.g. `علی کریمی / 09121234567`). Every digit is legible, so a leaked copy names its source.
  The number goes only to its owner and is never logged.
- Appearance: low-opacity white with a dark shadow so it survives on both bright and dark
  frames.
- Movement: one mark that jumps between the four corners and the exact centre of the picture
  at intervals from a per-session seed, so it cannot be cropped out of a whole recording — the
  centre catches a camera zoomed in past the corners — and the rhythm cannot be predicted.
- The player refuses to start if the overlay fails to attach. This check lives in Rust, not
  Dart.

**Phase 2 (M7) — forensic A/B watermarking.** Each segment is encoded twice with
imperceptible differences; each user receives a unique sequence of A/B choices, which encodes
their account id. Survives re-encoding, screen capture and camera recording. Costs ~2× storage
on watermarked renditions, so it is applied to high-value courses only.

## Layer 7 — Capture and environment blocking

| Platform | Mechanism |
|---|---|
| Android | `WindowManager.LayoutParams.FLAG_SECURE` on the player activity — blocks screenshots and screen recording at the OS level, and blanks the window in the recents list. |
| Windows | `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` — the window is excluded from capture APIs, so OBS/Teams/Snipping Tool record a blank region. (The live classroom uses `WDA_MONITOR` for students so the censorship is visible — ADR-0011.) |
| macOS | `NSWindow.sharingType = .none` — effective up to macOS 14; **ScreenCaptureKit on macOS 15+ ignores it**, so detection is the only barrier there. |
| iOS | `sceneCaptureState` detection + secure-layer rendering; no OS-level block exists. |
| All | Refuse playback on virtual/mirrored displays, in emulators/VMs (M3+), and on rooted/jailbroken devices; detect known screen-recorder processes on Windows and macOS. |

The blocking and detection code is shared: `packages/capture_guard` (Flutter plugin, all four
platforms), built for the live classroom and available to the player.

Every one of these is defeatable by a sufficiently determined attacker. They are included
because they stop the *casual* copier, who is the overwhelming majority.

Because `WDA_EXCLUDEFROMCAPTURE` also breaks legitimate remote support and accessibility
tools, `courses.allow_capture` can disable it per course.

## Layer 8 — Build and runtime hardening

- `flutter build --obfuscate --split-debug-info=...` on every release build.
- Rust compiled with `panic = "abort"`, symbols stripped, LTO.
- Anti-debug checks in Rust at playback start (`IsDebuggerPresent` / `ptrace` self-attach /
  `TracerPid`), plus periodic re-checks during playback.
- App signature verification at startup — a repackaged APK fails.
- No content key, KEK, LSK or signing material in the client binary. The only embedded secret
  is the license **public** key, which is safe to publish.
- Certificate pinning as in Layer 1.

## Live class protection

The same identity and capture rules apply to the live classroom, because a live class is
unreleased content too. Full design in [11-live-classroom.md](11-live-classroom.md) §8–9 and
[ADR-0011](adr/0011-live-capture-guard-censor-and-attribute.md):

- LiveKit join tokens are short-lived, minted per user per room after an enrollment check.
  The user id is the LiveKit identity, so one account is one seat — a second device joining
  replaces the first. The phone number never enters LiveKit metadata, which every participant
  can read.
- **Capture is blocked, detected and censored**, via `packages/capture_guard`:
  - Windows students get `WDA_MONITOR`, so captures show a black box; presenters get
    `WDA_EXCLUDEFROMCAPTURE`.
  - Android uses `FLAG_SECURE`.
  - macOS uses `sharingType = .none` plus recorder detection. On macOS 15+ this is detection
    only.
  - iOS uses capture-state detection plus a secure layer.
  - On detection the student's classroom is replaced by a censor screen, remote audio is muted,
    and the host is alerted.
- An identity watermark (full name, full phone beneath it) jumps between the four corners and
  the centre of the stage.
- **There is no client-side recording path at all.** Recording happens only server-side via
  Egress. The app ships without the capability.

## What to build when

| Layer | Milestone |
|---|---|
| 1 Transport, 2 At rest | M1 (with the API) |
| 3 Online playback + loopback server | M3 |
| 4 `.tihex` offline container | M4 |
| 5 Licenses | M4 (schema and signing in M1) |
| 6 Visible watermark | M3 · forensic A/B in M7 |
| 7 Capture blocking | M3 |
| 8 Hardening | M3, then reviewed every release |
