# capture_guard

Blocks and detects screen capture on Windows, macOS, Android and iOS, for the TIHE Live
classroom (and the player). Design and honest limits: [ADR-0011](../../docs/adr/0011-live-capture-guard-censor-and-attribute.md).

**Native code reports facts; Dart decides.** `CapturePolicyEngine` (pure Dart, unit-tested)
turns facts into a verdict — censor or not, and why — and `CaptureMonitor` wires it to the
platform: it blocks on start, polls and listens for facts, and emits verdicts for the UI and
reports for the host.

| Platform | Blocks with | Reports |
|---|---|---|
| Windows | `SetWindowDisplayAffinity` — `WDA_MONITOR` (black box) or `WDA_EXCLUDEFROMCAPTURE` | running processes, Remote Desktop |
| macOS | `NSWindow.sharingType = .none` (**ignored by ScreenCaptureKit on macOS 15+**) | running apps, mirrored displays |
| Android | `FLAG_SECURE` | Android 15 recording callback, Android 14 screenshots, extra displays |
| iOS | secure text-field layer (server flag) | capture state, extra screens, screenshots |

```dart
final monitor = CaptureMonitor(
  platform: MethodChannelCaptureGuard(),
  engine: CapturePolicyEngine(recorderProcesses: join.capturePolicy.recorderProcesses),
  block: join.capturePolicy.block,
  windowsAffinity: WindowsAffinity.monitor,
  iosSecureLayer: join.capturePolicy.iosSecureLayer,
);
monitor.verdicts.listen((v) => showCensor(v.censor));
monitor.reports.listen(gateway.reportCapture);
await monitor.start();
```

`example/` is the manual test bench for the device checklist in
[docs/11-live-classroom.md §12](../../docs/11-live-classroom.md): start a recorder and watch
it censor itself.

Nothing here builds in CI except the Dart (the native code needs each platform's toolchain);
the policy and monitor are covered by `flutter test`.
