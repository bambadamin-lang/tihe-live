# apps/player

The TIHE Live client: a protected course library for Windows and Android, iOS to follow.

## Running it

```bash
flutter pub get
flutter run -d windows            # or: flutter run -d android
```

It expects the API at `http://localhost:3000/v1`. Point it elsewhere with:

```bash
flutter run -d windows --dart-define=TIHE_API_URL=https://api.tihe.ir/v1
```

Sign in with a seeded student (`09125550003`) — the OTP prints to the API console, and the
development server returns it in the response, so the code field is prefilled.

## Layout

```
lib/
├── core/
│   ├── api/            client, error envelope, models, repositories
│   ├── security/       token store, device identity, masked logging
│   ├── theme/          design tokens, colours, type scale, icons, Jalali formatting
│   ├── router/         go_router with the auth redirect and the app shell
│   ├── preferences.dart  appearance (dark by default), app version
│   └── providers.dart  Riverpod wiring
├── ui/                 the design system: buttons, fields, rows, tabs, dialogs, states…
├── features/
│   ├── shell/          sidebar / rail / bottom bar, splash
│   ├── auth/           phone + OTP sign-in
│   ├── library/        home: continue learning, all courses
│   ├── search/         courses and sessions
│   ├── course/         sections and sessions
│   ├── player/         controller, controls, playback screen, identity watermark
│   ├── devices/        device management
│   └── account/        profile, appearance, shortcuts, sign-out
└── l10n/               Persian and English ARB files
```

## Design system

Screens build only from `lib/ui/` and the tokens in `lib/core/theme/`, so the app reads as one
product:

- **Colour** — `AppColors` (a `ThemeExtension`): neutral surfaces carry the interface; the single
  accent marks what is primary, selected, focused or in progress. Dark and light are both complete.
- **Type** — Vazirmatn at 400/500/600, scale in `AppTheme.textTheme`. Letter spacing stays zero:
  tracking breaks Persian joins.
- **Spacing, radius, motion** — `AppSpace` (4-pt grid), `AppRadius` (6/8/12), `AppMotion` (120–260 ms).
- **Icons** — Lucide only, through `AppIcons`. Directional glyphs mirror under RTL; player
  transport never does.
- **Interaction** — every clickable thing is a `Pressable`, so hover, press, keyboard focus ring and
  disabled behave the same everywhere.
- **Layout** — `WindowSize` switches pattern, not scale: bottom bar under 600 px, icon rail to
  1024 px, sidebar above. Pages centre at a readable width with a gutter that grows with the window.

## What is deliberately not here yet

**No content key ever enters Dart.** Key unwrapping, licence verification, the `.tihex` container and
the loopback HLS server all live in `packages/secure-core` (Rust), reached over FFI from M3. See
[`docs/03-content-protection.md`](../../docs/03-content-protection.md) and
[`docs/adr/0008`](../../docs/adr/0008-loopback-hls-server-for-playback.md).

That is why `PlayerScreen` shows a placeholder where the video surface goes rather than playing the
manifest URL directly. The full player chrome is in place — timeline with chapters, transport,
volume, speed/quality/subtitles, fullscreen, keyboard shortcuts — driving a `PlayerController` that
the engine binds to in M3; until then position moves only when the student seeks. Wiring a plain player against that URL would work today — and would be an
unprotected playback path, which is exactly the kind of shortcut that survives into a release. The
watermark overlay is already in place, on the same frame, so the video arrives into a screen that
already marks it.

`DeviceIdentity` likewise produces a real fingerprint but a placeholder public key, with a `TODO(M3)`
at the one line that changes when `secure-core` generates and seals the real keypair.

## Two video engines, one input

`media_kit` (libmpv) on Windows, `video_player` (ExoPlayer) on Android and iOS — the first-party
plugin is weak on Windows, and libmpv is not the best choice on mobile. Both are fed identical
plaintext HLS by the loopback server, so the split costs one abstraction rather than two playback
implementations. Reasoning in [`docs/adr/0001`](../../docs/adr/0001-flutter-for-all-clients.md).

## Persian and RTL

- `Directionality` is asserted at the app root rather than inferred, so a widget that forgets it
  still lays out correctly.
- The locale is fixed to `fa`, not taken from the system: the institute's content is Persian, and a
  student whose phone is in English still wants a Persian interface.
- All user-facing numbers go through `JalaliFormat.toPersianDigits`, and dates through the Jalali
  formatters. The database is UTC; conversion happens only here.
- Text scaling is clamped to 0.9–1.4 so a large system font cannot break the player controls while
  still respecting a student who needs bigger text.
- Vazirmatn carries both Persian and Latin glyphs, so a mixed title does not change face mid-line.
  Licensed under the OFL; see `assets/fonts/OFL.txt`.

## Testing

```bash
flutter analyze
flutter test
```

The tests target the logic that fails silently: Jalali and digit formatting, model parsing against
partial responses, error classification (which decides whether the student is sent to sign-in, to the
device manager, or to support), phone masking, and the watermark's own properties — that it drifts,
that it never swallows a tap, and that it survives a degenerate layout.
