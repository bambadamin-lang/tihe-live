# ADR-0001 — Flutter for all client platforms

**Status:** Accepted · 2026-09-27 · Platform scope superseded by
[ADR-0009](0009-four-platforms-classroom-desktop-first.md): Windows, macOS, Android and iOS are all
launch targets.

## Context

We must ship Windows and Android now, iOS later, with two developers. Only one of them works
on the client. The client is not a thin shell: it needs background downloads, OS keystore
access, screen-capture blocking, in-memory decryption and a local HTTP server.

Alternatives considered: React + Tauri + Capacitor; React Native + Electron; .NET MAUI.

## Decision

Flutter, one codebase, targeting Windows and Android now and iOS in M7.

## Consequences

**Good.** One UI layer, not two or three. FFI reaches Rust directly, which is where all the
protection logic lives. First-class RTL and Persian text shaping. One plugin layer for the
native work rather than per-platform reimplementation.

**Bad.** Dart is new to the team. The first-party `video_player` plugin has weak Windows
support, so Windows uses `media_kit` (libmpv) and Android uses `video_player` (ExoPlayer) —
two engines behind one abstraction, which is a real cost we accept because the loopback server
gives both the same plaintext HLS input.

**Rejected because.** Tauri/Capacitor pushes every native requirement into three separate
plugin implementations. React Native + Electron means two UI layers. .NET MAUI has the weakest
mobile ecosystem for video and would have been the only stack not shared with the backend.
