# ADR-0011 — Live class capture: block, detect, censor, alert, attribute

**Status:** Accepted · 2026-09-27 · Extends [03-content-protection.md](../03-content-protection.md)
Layer 7 to the live classroom.

## Context

The institute's requirement: screen recording is banned in class, and recording the screen or
the app window must produce censored output. A watermark in a corner must identify the viewer.

What the operating systems actually allow:

- **Windows**: `SetWindowDisplayAffinity`. `WDA_MONITOR` makes captures show a black box.
  `WDA_EXCLUDEFROMCAPTURE` (Windows 10 2004+) removes the window from captures entirely.
- **Android**: `FLAG_SECURE` blacks out screenshots and recordings.
- **macOS**: `NSWindow.sharingType = .none` worked until macOS 14. **macOS 15+
  ScreenCaptureKit ignores it**, and there is no public replacement API.
- **iOS**: no API to block recording. `sceneCaptureState` (formerly `isCaptured`) reports it,
  and rendering inside a secure text-field layer hides content from captures. That trick
  relies on a private view hierarchy that has changed between iOS versions.
- **No platform can exclude audio from a capture.**

## Decision

1. **Block** with the strongest mechanism each platform has:
   - Students on Windows get `WDA_MONITOR`, so captures show a visibly censored black box.
     Presenters and hosts get `WDA_EXCLUDEFROMCAPTURE`, so their own screen share doesn't
     contain a black hole. If a call fails, fall back to `WDA_MONITOR`.
   - Android uses `FLAG_SECURE` while the classroom is on screen.
   - macOS uses `sharingType = .none`.
   - iOS uses the secure layer, behind a server flag so it can be turned off if an iOS update
     breaks it.
2. **Detect**: OS callbacks (Android 14/15), iOS capture state and external screens, Remote
   Desktop, and scans for known recorder processes on Windows and macOS. The process list
   comes from the server.
3. **Censor on detection**: the classroom is replaced by a censor screen **and remote audio is
   muted**, until the recording stops.
4. **Alert and audit**: the client reports to the gateway. The gateway writes a
   `live_audit_events` row and alerts everyone with `participants.manage`. **No auto-kick** —
   the host decides.
5. **Attribute always**: an identity watermark (masked phone · short id · time) hops between
   the stage's corners. It is a Flutter overlay: in the classroom the video is itself a Flutter
   texture, so this is equivalent to the native layer docs/03 asks for in the player.
6. **Architecture**: `packages/capture_guard` is a Flutter plugin in which **native code
   reports facts and Dart decides**. The policy engine is pure Dart and unit-tested on Linux.
   The plugin is offered to the video player, which needs the same rules.

## Consequences

**Good.** Casual recording (built-in recorders, OBS, Snipping Tool, phone screen recorders)
produces black or censored output on Windows, Android and iOS. The host learns about every
attempt, and every frame that does leak names its account.

**Bad — stated plainly.**
- **macOS 15+**: the window itself is not blanked. Detection is heuristic, and a recorder we do
  not know about gets through. The watermark is the real control there.
- **A camera or HDMI capture card defeats all of this** (see docs/08, T3). The watermark makes
  such copies attributable.
- **Recorder detection has false positives**: a student with OBS merely open is censored until
  they close it. That is the intended behaviour.
- `FLAG_SECURE` / WDA also blank legitimate accessibility and remote-support tools during
  class. Courses with `allowCapture` can turn blocking off, as for the player.
