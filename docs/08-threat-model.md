# Threat Model

The purpose of this document is to be honest. A protection scheme that is oversold is worse
than a weak one, because decisions get made on a false belief.

We rank attackers by capability and state, for each, what stops them and what does not.

---

## T1 — The casual sharer

*A student who would forward a video file to a classmate if it were easy.*

**This is the overwhelming majority of real-world leakage.**

| Attempt | Outcome |
|---|---|
| Copy the downloaded file to a friend | **Stopped.** `.tihex` is sealed to their device key; the file will not open. |
| Share their account | **Limited.** `maxDevices` and `maxConcurrentStreams` cap it, and the watermark shows whose account it is. |
| Screenshot or screen-record on their phone | **Stopped.** Android `FLAG_SECURE`. |
| Record with OBS/Snipping Tool on Windows | **Stopped.** `WDA_EXCLUDEFROMCAPTURE` yields a blank region. |
| Find the video URL in their browser | **N/A.** No web playback; segments are encrypted and presigns expire in 2 minutes. |

**Verdict: effectively stopped.** This is where the protection investment pays off.

---

## T2 — The technical student

*Comfortable with dev tools, will spend an evening on it, no reverse-engineering experience.*

| Attempt | Outcome |
|---|---|
| Intercept HTTPS with a proxy to grab keys | **Stopped.** Certificate pinning; and the key on the wire is sealed to the device key. |
| Pull segments from MinIO with the presigned URL | **Partly.** They get ciphertext. Useless without the CEK. |
| Read the key out of the Dart heap | **Stopped.** No key ever enters Dart. |
| Hit the loopback server directly and save plaintext segments | **This works.** See "known weakness" below. |
| Edit the `.tihex` header to extend expiry | **Stopped.** Ed25519 signature over the header. |
| Set the system clock back to revive an expired licence | **Stopped.** Monotonic counter + sealed last-known server time. |
| Play in an emulator with capture enabled | **Stopped in M3+** by emulator detection. |

**Verdict: mostly stopped, one real gap.**

### Known weakness: the loopback server

The loopback server serves plaintext segments to the local video engine. Anyone who finds the
random port and the per-launch token can request those segments themselves and reassemble the
video. Mitigations in place:

- Random port and 256-bit per-launch token, never logged, never written to disk.
- Bound to `127.0.0.1` only, so it is not reachable off-device.
- Segments are served **once**; a second request for the same segment in the same session is
  refused (the engine does not re-request in normal playback).
- Serving is rate-limited to roughly real-time playback speed, so dumping a 90-minute lecture
  takes 90 minutes rather than seconds.
- The token rotates per playback session.

This is the structural cost of not having hardware DRM: the plaintext must reach the decoder
somehow, and without a secure video path, that somehow is reachable. Widevine L1 closes it by
keeping the plaintext inside the TEE, which is exactly why it is on the M7 list.

---

## T3 — The determined reseller

*Wants to resell the course. Will buy hardware and spend weeks.*

| Attempt | Outcome |
|---|---|
| HDMI capture card on the Windows output | **Not stopped.** Nothing short of HDCP-enforced hardware DRM stops this, and even that is broken by cheap splitters. |
| Point a camera at the screen | **Not stopped.** Unstoppable by definition. |
| Reverse-engineer `secure-core`, extract the key unwrap logic | **Slowed, not stopped.** Obfuscation, stripping and anti-debug raise the cost to days of skilled work. The device private key still cannot be exported from the keystore, so they must run the attack on their own enrolled device — which identifies them. |
| Patch the app to remove the watermark | **Stopped in the common case.** The overlay is native-layer and its presence is verified in Rust; app-signature verification fails a repackaged build. A full custom build of the app from a reverse-engineered core defeats this. |
| Buy many accounts to farm content | **Detectable.** `watch_events` shows the pattern; licences are revocable. |

**Verdict: not stopped — but attributable.** Every copy they make carries a watermark
identifying the account it came from, so we can revoke it, and the institute has evidence.
This is the honest ceiling, and it is the same ceiling SpotPlayer operates under.

---

## T4 — Server-side compromise

*Attacker gets into the infrastructure.*

| Reach | Consequence |
|---|---|
| MinIO credentials | Ciphertext only. No CEK, no plaintext. |
| Postgres read access | Wrapped CEKs only — useless without the KEK, which lives in the API environment, not the database. |
| API server compromise (KEK + LSK) | **Total loss.** Every video is decryptable and arbitrary licences can be minted. |

Mitigations: the API host runs nothing else; KEK and LSK come from the environment (path to
Vault documented in `infra/`); DB and MinIO credentials are scoped and rotatable; all
licence issuing and key unwrapping is audit-logged so an intrusion is at least reconstructable.
LSK rotation is the break-glass response and invalidates every outstanding licence.

---

## T5 — Insider

*A teacher or staff member with legitimate access.*

Largely out of scope for technical controls: a teacher has the source recording before we do.
What we do have is audit logging on every download, licence issue and admin action, and
watermarks that apply to staff accounts too.

---

## Summary

| Attacker | Stopped? |
|---|---|
| T1 Casual sharer | **Yes** |
| T2 Technical student | **Mostly** — loopback dump is the gap |
| T3 Determined reseller | **No** — but every leak is attributable |
| T4 Server compromise | Contained below the API; API compromise is total |
| T5 Insider | Not technically; audited |

**The design goal, restated:** make extraction cost more than the content is worth, and make
every leak traceable. Not "make copying impossible" — that product does not exist.

## What would move the ceiling

In rough order of value per unit of effort:

1. **Widevine L1 (Android) + PlayReady (Windows)** — closes the T2 loopback gap by keeping
   plaintext inside the TEE. Needs a vendor relationship and, in practice, a reachable
   provider. M7.
2. **Forensic A/B watermarking** — makes T3's camera and capture-card copies traceable even
   after re-encoding. Buildable by us. M7.
3. **Behavioural detection** — flag accounts whose `watch_events` look like farming rather
   than studying. Cheap, and the data is already collected from M1.
