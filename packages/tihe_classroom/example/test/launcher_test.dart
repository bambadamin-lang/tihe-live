import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/tihe_classroom.dart';
import 'package:tihe_classroom_example/main.dart';
import 'package:tihe_classroom_example/updater.dart';

/// The launcher: the demo and server cards, the server lamp, and — on request — its
/// screenshots for docs/images/classroom, in Modam from the package's assets (TIHE_FONT_DIR,
/// optional, holds a fallback for the few characters Modam lacks):
///
///   TIHE_SCREENSHOTS=1 TIHE_FONT_DIR=/path/to/vazirmatn flutter test --update-goldens
final _shots = Platform.environment['TIHE_SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  expect(await ClassroomFonts.ensureLoaded(), isTrue, reason: 'Modam assets');
  // Modam has no "…", "·" or "²"; on a device the platform's fonts fill them in, here a
  // fallback in the theme's list does, if given.
  final fallback = Platform.environment['TIHE_FONT_DIR'];
  if (fallback != null) {
    final loader = FontLoader('Vazirmatn');
    for (final f in Directory(
      fallback,
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font
        in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// Renders a screenshot with shadows drawn as the app draws them (tests draw them hard-edged
/// unless told otherwise). The flag must be back on by the end of each test.
Future<void> _shoot(
  WidgetTester tester,
  String name, {
  Size size = const Size(1600, 900),
  Brightness brightness = Brightness.dark,
  AppUpdates? updates,
}) async {
  debugDisableShadows = false;
  try {
    await _pump(tester, size: size, brightness: brightness, updates: updates);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
    await tester.pumpWidget(const SizedBox());
  } finally {
    debugDisableShadows = true;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1600, 900),
  Future<bool> Function(String)? ping,
  Brightness brightness = Brightness.dark,
  AppUpdates? updates,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    ClassroomExampleApp(ping: ping ?? (_) async => true, updates: updates),
  );
  // Frame by frame, so the cards' entrance animations run to the end.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    if (_shots) await _loadFonts();
  });

  testWidgets('shows both ways in, and the server lamp', (tester) async {
    await _pump(tester);
    expect(find.text('کلاس نمایشی'), findsOneWidget);
    expect(find.text('اتصال به سرور'), findsOneWidget);
    expect(find.text('آنلاین'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unreachable server turns the lamp red', (tester) async {
    await _pump(tester, ping: (_) async => false);
    expect(find.text('سرور در دسترس نیست'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('editing the address checks the new one', (tester) async {
    final asked = <String>[];
    await _pump(
      tester,
      ping: (url) async {
        asked.add(url);
        return url.contains('tihe.ir');
      },
    );
    expect(find.text('آنلاین'), findsNothing);
    await tester.enterText(
      find.byType(TextField).first,
      'https://live.tihe.ir/v1/live',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(asked.last, 'https://live.tihe.ir/v1/live');
    expect(find.text('آنلاین'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('picks a role and a starting layout, then opens the demo', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('دانشجو'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('تخته سفید'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('گفتگو').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('گفتگو'), findsOneWidget);
    await tester.tap(find.text('ورود به کلاس نمایشی'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ClassroomPage), findsOneWidget);
    // A student: the hand, not the end of class.
    expect(find.byType(HandToggle), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  /// An update downloaded and checked, ready to install.
  AppUpdates readyUpdate({required void Function() onInstalled}) =>
      AppUpdates(
        Updater(currentVersion: '0.1.56', directory: Directory.systemTemp),
        launch: (_) async {},
        quit: onInstalled,
      )..debugReady(
        UpdateManifest(
          version: '0.1.57',
          url: Uri.parse(
            'https://github.com/bambadamin-lang/tihe-live/releases/download/live-v0.1.57/TIHE-Live-Setup-0.1.57.exe',
          ),
          sha256: '0' * 64,
        ),
        File('TIHE-Live-Setup-0.1.57.exe'),
      );

  testWidgets('offers a downloaded update and installs it on request', (
    tester,
  ) async {
    var installed = false;
    await _pump(
      tester,
      updates: readyUpdate(onInstalled: () => installed = true),
    );
    expect(find.textContaining('نسخهٔ تازهٔ برنامه (۰.۱.۵۷)'), findsOneWidget);
    await tester.tap(find.text('نصب و اجرای دوباره'));
    await tester.pump();
    expect(installed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('says nothing when there is no update', (tester) async {
    await _pump(tester);
    expect(find.text('نصب و اجرای دوباره'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('welcome, update ready', skip: !_shots, (tester) async {
    await _shoot(
      tester,
      'welcome-update',
      updates: readyUpdate(onInstalled: () {}),
    );
  });

  testWidgets('welcome, dark', skip: !_shots, (tester) async {
    await _shoot(tester, 'welcome');
  });

  testWidgets('welcome, light', skip: !_shots, (tester) async {
    await _shoot(tester, 'welcome-light', brightness: Brightness.light);
  });

  testWidgets('welcome, phone', skip: !_shots, (tester) async {
    await _shoot(tester, 'welcome-phone', size: const Size(390, 844));
  });
}
