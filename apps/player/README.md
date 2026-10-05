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
- The app is set in Modam, registered from the classroom package at start-up, so the app and its
  classes share one family. Its standard cut carries Latin glyphs too, so a mixed title does not
  change face mid-line. Vazirmatn (OFL; see `assets/fonts/OFL.txt`) covers the few characters
  Modam lacks.

## Testing

```bash
flutter analyze
flutter test
```

The tests target the logic that fails silently: Jalali and digit formatting, model parsing against
partial responses, error classification (which decides whether the student is sent to sign-in, to the
device manager, or to support), phone masking, and the watermark's own properties — that it drifts,
that it never swallows a tap, and that it survives a degenerate layout.

## Install on Windows

`.github/workflows/windows-installer.yml` builds the app on a Windows runner and wraps it in a
Persian setup wizard, `TIHE-Setup-<version>.exe` (Inno Setup,
[`installer/windows/tihe_live.iss`](installer/windows/tihe_live.iss)). The workflow
runs on pull requests that touch the app or the classroom and on `live-v*` tags, which also publish a
GitHub release. Download the `.exe` from the run's **Artifacts**. Once the workflow is on
`main`, it can also be started by hand from the Actions tab (**Run workflow**, with an
optional version); GitHub only offers that for workflows on the default branch.

The wizard:
1. welcome
2. install folder (per user, no administrator needed)
3. **institute server address** (the server's one address, e.g. `http://192.168.1.10:8080`), pre-filled
   with the repository variable `TIHE_SERVER_URL`; installs over the old classroom app turn its
   `…:3100/v1/live` address into the gateway's `…:8080`
4. desktop shortcut
5. install and start

It needs Windows 10 version 2004 or later, the first release that can hide a window from
screen capture. The Visual C++ runtime is bundled, and every build runs
[`check-dependencies.ps1`](installer/windows/check-dependencies.ps1): it reads what
each bundled `.exe` and `.dll` imports and fails if a DLL loaded at start-up is neither in the
bundle nor part of Windows. Uninstall from Windows Settings → Apps.

For IT staff: `TIHE-Setup-0.1.0.exe /VERYSILENT /server=https://…` installs with no
questions.

The installer is **not code-signed yet**, so Windows SmartScreen warns on first run ("Windows
protected your PC" → **More info** → **Run anyway**). Signing needs a code-signing
certificate in the institute's name; add it to the workflow as a secret when there is one.

To build it by hand on a Windows PC with Flutter, Visual Studio (C++ desktop) and
Inno Setup 6.5+:

```powershell
cd apps\player
flutter build windows --release
installer\windows\check-dependencies.ps1 -Bundle build\windows\x64\runner\Release -BundleVcRuntime
iscc /DDefaultServer=http://your-server:8080 installer\windows\tihe_live.iss
# → installer\windows\Output\TIHE-Setup-0.1.0.exe
```

## Updates

The Windows app updates itself from GitHub releases
([`lib/core/update/updater.dart`](lib/core/update/updater.dart)). This repository is private, so a
`live-v*` tag publishes the wizard twice: as a release here, and as a release in a **public,
code-free repo** that installed apps read without a token. By default that repo is
`bambadamin-lang/tihe-live-releases`; the `TIHE_UPDATE_REPO` repository variable overrides it.

The app checks at start-up and every six hours. When there is a newer version it shows a
banner on the dashboard, never in class or the player; Account → **Check for updates** asks
at once. **Update** downloads the wizard and checks its
size and SHA-256 against `latest.json` before running it. The wizard then runs silently,
keeps the server address, and starts the app again. A per-machine install still raises the
UAC prompt. **Later** hides that version until a newer one is published.

Setup, once:
1. Create the public repo with a README. A release needs a commit to tag.
2. Create a fine-grained token with **Contents: read and write** on that repo only. Save it
   here as the `RELEASES_TOKEN` Actions secret. Without it, tags still build, but installed
   apps are not offered the version (the run shows a warning).

To release, push a tag such as `live-v0.2.0`. Versions are `major.minor.patch`. Each release in
the public repo carries `TIHE-Setup-<version>.exe` and `latest.json`:

```json
{ "version": "0.2.0", "windows": { "file": "TIHE-Setup-0.2.0.exe", "sha256": "…", "size": 41234567 } }
```

The app fetches `releases/latest/download/latest.json`, a plain download rather than the
REST API, so a classroom behind one IP address does not hit GitHub's hourly API limit. It
builds the wizard's URL from the `live-v<version>` tag. Only builds from the workflow can
update, because they carry `--dart-define=TIHE_APP_VERSION` and `TIHE_UPDATE_REPO`. Local
`flutter run` builds never update, and neither do macOS, Android or iOS, since only the
Windows wizard is published.

The hash catches corrupt or swapped downloads, but not a compromised releases repo, because
the hash comes from the same place. Code signing (see above) is what would close that gap.
Keep write access to the releases repo as tight as access to this one.
