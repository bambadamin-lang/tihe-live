@TestOn('vm')
library;

import 'dart:io';

import 'package:capture_guard/capture_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/src/ui/controls/bars.dart';
import 'package:tihe_classroom/src/ui/controls/layout_picker.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// Screenshots of the classroom for review (docs/images/classroom). Not a regression test:
/// they depend on fonts loaded from the machine, so they run only on request:
///
///   TIHE_SCREENSHOTS=1 TIHE_FONT_DIR=/path/to/ttf flutter test test/screenshots --update-goldens
///
/// TIHE_FONT_DIR should hold a Persian font (Peyda once provided; Vazirmatn meanwhile), which is
/// registered as the Peyda family so the theme picks it up.
final _enabled = Platform.environment['TIHE_SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  final dir = Platform.environment['TIHE_FONT_DIR'];
  if (dir != null) {
    final peyda = FontLoader('Peyda');
    for (final f in Directory(
      dir,
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
      peyda.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await peyda.load();
  }
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter-sdk/flutter';
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

class _RecordingPlatform implements CaptureGuardPlatform {
  @override
  bool get scansProcesses => true;
  @override
  Future<BlockResult> enableBlocking({
    required WindowsAffinity windowsAffinity,
    required bool iosSecureLayer,
  }) async =>
      const BlockResult(active: true, mechanism: 'wda_monitor', failed: false);
  @override
  Future<void> disableBlocking() async {}
  @override
  Future<CaptureFacts> readFacts() async => const CaptureFacts();
  @override
  Future<List<String>> runningProcesses() async => [
    'explorer.exe',
    'obs64.exe',
  ];
  @override
  Stream<CaptureEvent> get events => const Stream.empty();
}

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  required Size size,
  String as = DemoClassroom.host,
  Layout? layout,
  bool hostSharing = false,
  CaptureMonitor? capture,
  Future<void> Function(WidgetTester tester)? then,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final demo = DemoClassroom.build(
    as: as,
    layout: layout,
    hostSharing: hostSharing,
    capture: capture,
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ClassroomPage(session: demo.session),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (then != null) await then(tester);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  const desktop = Size(1600, 900);

  testWidgets('host at the whiteboard', skip: !_enabled, (tester) async {
    await _shoot(tester, 'host-whiteboard', size: desktop);
  });

  testWidgets('student during a presentation', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      'student-presentation',
      size: desktop,
      as: DemoClassroom.ali,
      layout: layoutPresets[LayoutPreset.presentation],
      hostSharing: true,
    );
  });

  testWidgets('host in discussion with raised hands', skip: !_enabled, (
    tester,
  ) async {
    await _shoot(
      tester,
      'host-discussion',
      size: desktop,
      layout: layoutPresets[LayoutPreset.discussion],
    );
  });

  testWidgets('host in the split layout', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      'host-split',
      size: desktop,
      layout: layoutPresets[LayoutPreset.split],
      hostSharing: true,
    );
  });

  testWidgets('student censored while recording', skip: !_enabled, (
    tester,
  ) async {
    await _shoot(
      tester,
      'student-censored',
      size: desktop,
      as: DemoClassroom.ali,
      capture: CaptureMonitor(
        platform: _RecordingPlatform(),
        engine: CapturePolicyEngine(recorderProcesses: ['obs64.exe']),
        block: true,
        windowsAffinity: WindowsAffinity.monitor,
        iosSecureLayer: false,
      ),
    );
  });

  testWidgets('layout picker', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      'host-layout-picker',
      size: desktop,
      then: (tester) async {
        final context = tester.element(find.byType(ControlBar));
        showClassroomDialog<void>(context, const LayoutPickerSheet());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(LayoutPickerSheet), findsOneWidget);
      },
    );
  });

  testWidgets('layout editor', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      'host-layout-editor',
      size: desktop,
      then: (tester) async {
        final context = tester.element(find.byType(ControlBar));
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => UncontrolledProviderScope(
              container: ProviderScope.containerOf(context),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Theme(
                  data: buildClassroomThemeData(),
                  child: LayoutEditor(
                    initial: layoutPresets[LayoutPreset.split]!.pods,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(LayoutEditor), findsOneWidget);
      },
    );
  });

  testWidgets('student on a phone', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      'student-phone',
      size: const Size(390, 844),
      as: DemoClassroom.sara,
    );
  });
}
