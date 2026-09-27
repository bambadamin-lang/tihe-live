# ADR-0009 — Four platforms; the classroom ships desktop-first

**Status:** Accepted · 2026-09-27 · Supersedes the platform scope in
[ADR-0001](0001-flutter-for-all-clients.md) and closes open question Q10.

## Context

ADR-0001 targeted Windows and Android, with iOS in M7 and macOS parked. The institute has since
stated that the app is for **Windows, Android, iOS and macOS**. Teachers mostly host classes
from laptops and desktops; students join from anything.

## Decision

- All four platforms are launch targets for the app. Flutter already builds all four from one
  codebase, so this changes scope and testing, not the stack.
- The live classroom is built **desktop-first**: Windows and macOS, then Android, then iOS.
  Hosting a class (screen share, layout editor, whiteboard with a mouse or pen) is a desktop
  activity; joining one works everywhere.
- Linux builds are used for development and CI (widget and golden tests) only.

## Consequences

**Good.** One app for every student device. macOS support removes the most common reason
teachers would need a second machine.

**Bad.**
- Each platform has its own capture-blocking mechanism with its own limits (ADR-0011). In
  particular, macOS 15+ cannot block capture at all.
- iOS screen sharing needs a Broadcast Upload Extension and an app group, with separate
  signing.
- The video library must also build `packages/secure-core` for iOS and macOS. That is the
  video session's call on timing; this ADR only makes the platforms in-scope.
- CI moves from Flutter 3.24 to current stable (3.47), because `livekit_client` 2.x requires
  Flutter ≥ 3.38.
