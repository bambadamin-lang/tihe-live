import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/tihe_classroom.dart';
import 'package:tihe_classroom_example/main.dart';

/// The launcher: the demo and server cards, the server lamp, and — on request — its
/// screenshots for docs/images/classroom:
///
///   TIHE_SCREENSHOTS=1 TIHE_FONT_DIR=/path/to/ttf flutter test --update-goldens
final _shots = Platform.environment['TIHE_SCREENSHOTS'] == '1';

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
}) async {
  debugDisableShadows = false;
  try {
    await _pump(tester, size: size, brightness: brightness);
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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(ClassroomExampleApp(ping: ping ?? (_) async => true));
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
