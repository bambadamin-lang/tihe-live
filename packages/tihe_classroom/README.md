# tihe_classroom

The TIHE Live classroom as a Flutter package. It covers:
- the stage and its layouts
- webcam and screen share
- the whiteboard
- raised hands and access levels
- capture censoring
- the identity watermark

The UI is in Persian, right to left, in Peyda, in a glass theme with light and dark modes. It
follows the host app's theme unless given `brightness:`, and a switch in the class's top bar
flips it (reported through `onBrightnessChanged:`). Design and rules:
[docs/11-live-classroom.md](../../docs/11-live-classroom.md).

![Host at the whiteboard](../../docs/images/classroom/host-whiteboard.jpg)

## Use it

```dart
import 'package:tihe_classroom/tihe_classroom.dart';

final session = await openClassroom(
  liveApiBaseUrl: 'https://api.tihe.ir/v1/live',
  accessToken: auth.freshAccessToken,     // the API's access token, refreshed by the app
  sessionId: 'ses_01J8Z…',
);
// classroomRoute fades the class in from slightly larger; any route works.
Navigator.of(context).push(classroomRoute(
  context,
  (_) => ClassroomPage(session: session, onExit: (_) => Navigator.of(context).pop()),
));
```

If the class refuses the join (not enrolled, not started, locked, full, removed),
`openClassroom` throws `ApiError`, and `messageFa` holds the Persian message to show.
`ClassroomPage` owns the session: it opens it and disposes it.

## Inside

```
lib/src/contracts/   Dart mirror of packages/contracts/src/live, checked against its JSON fixtures
lib/src/data/        LiveApi (REST), GatewayClient (WebSocket, reconnect + replay), media port
                     with LiveKit and fake implementations
lib/src/domain/      ClassroomState and its reducer, board model, stage geometry, watermark
                     hopper, Persian digits and Jalali dates
lib/src/state/       ClassroomSession (gateway + media + capture guard), BoardController, providers
lib/src/ui/          theme (tokens, glass controls, Peyda loader), stage and pods, whiteboard,
                     bars and layout editor, censor screen, watermark
lib/src/demo/        an in-process gateway and a fixture class, for the demo and the tests
```

The server is authoritative, so the client never decides a rule on its own. It sends
commands and applies the events the gateway sends back. Where the UI acts before the server
confirms (whiteboard strokes), the action is marked pending until the matching event arrives.

## Peyda

Put the TTF/OTF files in [`assets/fonts/`](assets/fonts/README.md). They are found and
registered at runtime, so the package builds before the files are there. Until then it uses
the platform's Persian font.

## Run the example

```bash
cd packages/tihe_classroom/example
flutter run -d macos        # or windows, android, ios, linux
```

The launcher offers:
- **Demo**: an offline class. Pick a role (host, co-host, presenter, student) and a layout.
  An in-process gateway plays the other side, so hands, chat, the board and permissions
  all work without a server.
- **Server**: join a real `services/live` session. Give the base URL, the session id and an
  access token. Setting `TIHE_LIVE_URL`, `TIHE_SESSION` and `TIHE_TOKEN` joins straight away.
  Against a local services/live, mint tokens with
  `pnpm --filter @tihe/live dev-token <userId> <role>` (users are in
  `services/live/dev/directory.json`).

On Linux, `livekit_client` checks connectivity through NetworkManager over D-Bus. Without it,
as in containers, the gateway works but joining the media room fails. The desktop targets
that ship are Windows and macOS.

## Install on Windows

`.github/workflows/windows-installer.yml` builds the app on a Windows runner and wraps it in a
Persian setup wizard, `TIHE-Live-Setup-<version>.exe` (Inno Setup,
[`installer/windows/tihe_live.iss`](example/installer/windows/tihe_live.iss)). The workflow
runs on pull requests that touch the classroom and on `live-v*` tags, which also publish a
GitHub release. Download the `.exe` from the run's **Artifacts**. Once the workflow is on
`main`, it can also be started by hand from the Actions tab (**Run workflow**, with an
optional version); GitHub only offers that for workflows on the default branch.

The wizard:
1. welcome
2. install folder (per user, no administrator needed)
3. **class server address**, pre-filled with the repository variable `TIHE_LIVE_URL`
4. desktop shortcut
5. install and start

It needs Windows 10 version 2004 or later, the first release that can hide a window from
screen capture. The Visual C++ runtime is bundled, and every build runs
[`check-dependencies.ps1`](example/installer/windows/check-dependencies.ps1): it reads what
each bundled `.exe` and `.dll` imports and fails if a DLL loaded at start-up is neither in the
bundle nor part of Windows. Uninstall from Windows Settings → Apps.

For IT staff: `TIHE-Live-Setup-0.1.0.exe /VERYSILENT /server=https://…` installs with no
questions.

The installer is **not code-signed yet**, so Windows SmartScreen warns on first run ("Windows
protected your PC" → **More info** → **Run anyway**). Signing needs a code-signing
certificate in the institute's name; add it to the workflow as a secret when there is one.

To build it by hand on a Windows PC with Flutter, Visual Studio (C++ desktop) and
Inno Setup 6.5+:

```powershell
cd packages\tihe_classroom\example
flutter build windows --release
installer\windows\check-dependencies.ps1 -Bundle build\windows\x64\runner\Release -BundleVcRuntime
iscc /DDefaultServer=https://your-server/v1/live installer\windows\tihe_live.iss
# → installer\windows\Output\TIHE-Live-Setup-0.1.0.exe
```

## Updates

The Windows app updates itself from GitHub releases
([`example/lib/update.dart`](example/lib/update.dart)). This repository is private, so a
`live-v*` tag publishes the wizard twice: as a release here, and as a release in a **public,
code-free repo** that installed apps read without a token. By default that repo is
`bambadamin-lang/tihe-live-releases`; the `TIHE_UPDATE_REPO` repository variable overrides it.

The app checks at start-up and every six hours. When there is a newer version it shows a
banner on the start screen, never in class. **Update** downloads the wizard and checks its
size and SHA-256 against `latest.json` before running it. The wizard then runs silently,
keeps the server address, and starts the app again. A per-machine install still raises the
UAC prompt. **Later** hides that version until a newer one is published.

Setup, once:
1. Create the public repo with a README. A release needs a commit to tag.
2. Create a fine-grained token with **Contents: read and write** on that repo only. Save it
   here as the `RELEASES_TOKEN` Actions secret. Without it, tags still build, but installed
   apps are not offered the version (the run shows a warning).

To release, push a tag such as `live-v0.2.0`. Versions are `major.minor.patch`. Each release in
the public repo carries `TIHE-Live-Setup-<version>.exe` and `latest.json`:

```json
{ "version": "0.2.0", "windows": { "file": "TIHE-Live-Setup-0.2.0.exe", "sha256": "…", "size": 41234567 } }
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

## Test it

```bash
flutter analyze
flutter test                # contracts conformance, reducers, gateway client, session, board, page
(cd example && flutter test)  # self-update: versions, manifest, verified download, schedule
```

The screenshots in `docs/images/classroom/` come from an opt-in test. It needs a Persian TTF
(Peyda, or Vazirmatn as a stand-in) registered as the Peyda family:

```bash
TIHE_SCREENSHOTS=1 TIHE_FONT_DIR=/path/to/ttf flutter test test/screenshots --update-goldens
# PNGs land in test/screenshots/goldens/ (git-ignored); convert to JPEG for docs/images/classroom/
```
