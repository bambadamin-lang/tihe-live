import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tihe_classroom/tihe_classroom.dart' show ClassroomFonts;
import 'package:tihe_player/core/preferences.dart';
import 'package:tihe_player/core/providers.dart';
import 'package:tihe_player/core/router/app_router.dart';
import 'package:tihe_player/core/theme/app_theme.dart';
import 'package:tihe_player/features/player/player_controls.dart';
import 'package:tihe_player/main.dart';
import 'package:tihe_player/ui/ui.dart';

import 'support/fakes.dart';

/// Every screen, at every size class, with real fonts and realistic Persian content.
///
/// The layout switches pattern by window size (bottom bar, rail, sidebar) rather than scaling, so
/// each size is its own layout and each can overflow on its own. An overflow throws in a test, so
/// rendering is the assertion.
void main() {
  const sizes = {
    'phone': (Size(390, 844), TargetPlatform.android),
    'tablet': (Size(834, 1112), TargetPlatform.android),
    'desktop': (Size(1440, 900), TargetPlatform.windows),
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Real glyph metrics: the test font's square glyphs would hide (and invent) overflows.
    final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
    for (final family in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    // The app's own family is registered at runtime, as main() does, not declared in pubspec.
    ClassroomFonts.use(AppTheme.fontFamily);
    expect(await ClassroomFonts.ensureLoaded(), isTrue);
  });

  late FakePlayback playback;

  Future<ProviderContainer> pumpApp(
    WidgetTester tester,
    (Size, TargetPlatform) size, {
    AuthState? auth,
    ThemeMode mode = ThemeMode.dark,
  }) async {
    tester.view.physicalSize = size.$1;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = size.$2;

    playback = FakePlayback();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => FakeAuth(auth ?? AuthSignedIn(fakeSession))),
        themeModeProvider.overrideWith(() => FixedThemeMode(mode)),
        appVersionProvider.overrideWith((ref) async => '0.1.0'),
        catalogRepositoryProvider.overrideWithValue(FakeCatalog()),
        playbackRepositoryProvider.overrideWithValue(playback),
        coursesProvider.overrideWith((ref) async => fakeCourses),
        courseProvider.overrideWith((ref, id) async => fakeCourse),
        devicesProvider.overrideWith((ref) async => fakeDevices),
        searchProvider.overrideWith((ref, query) async => FakeCatalog().search(query)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const TiheApp()),
    );
    await tester.pump();
    return container;
  }

  Future<void> go(WidgetTester tester, ProviderContainer container, String location) async {
    container.read(routerProvider).go(location);
    // Skeletons and the watermark animate forever, so settle by time rather than pumpAndSettle.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    group(name, () {
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      for (final location in [
        '/library',
        '/course/crs_1',
        '/search',
        '/devices',
        '/account',
        '/watch/vid_2',
      ]) {
        testWidgets('$location renders', (tester) async {
          final container = await pumpApp(tester, size);
          await go(tester, container, location);
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        });
      }

      testWidgets('/library renders in light mode', (tester) async {
        final container = await pumpApp(tester, size, mode: ThemeMode.light);
        await go(tester, container, '/library');
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('/sign-in renders', (tester) async {
        final container = await pumpApp(tester, size, auth: const AuthSignedOut());
        await go(tester, container, '/sign-in');
        expect(tester.takeException(), isNull);
        // Phone and password.
        expect(find.byType(AppTextField), findsNWidgets(2));
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }

  testWidgets('navigation follows the window: bottom bar on a phone, sidebar on desktop', (
    tester,
  ) async {
    var container = await pumpApp(tester, sizes['phone']!);
    await go(tester, container, '/library');
    // The sidebar's search field carries the Ctrl K hint; the bottom bar does not.
    expect(find.byType(KeyCap), findsNothing);
    expect(find.text('حساب'), findsOneWidget);

    container = await pumpApp(tester, sizes['desktop']!);
    await go(tester, container, '/library');
    expect(find.byType(KeyCap), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('player transport reads left-to-right inside the RTL app', (tester) async {
    final container = await pumpApp(tester, sizes['desktop']!);
    await go(tester, container, '/watch/vid_2');

    final controls = find.byType(PlayerControls);
    expect(Directionality.of(tester.element(controls)), TextDirection.rtl);
    expect(Directionality.of(tester.element(find.byType(PlayerTimeline))), TextDirection.ltr);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('leaving the player ends its playback session', (tester) async {
    // Frees the concurrent-stream slot. Guards a dispose() that once threw before reaching end().
    final container = await pumpApp(tester, sizes['desktop']!);
    await go(tester, container, '/watch/vid_2');
    expect(playback.ended, isEmpty);

    await go(tester, container, '/library');
    expect(tester.takeException(), isNull);
    expect(playback.ended, ['pbs_vid_2']);
    debugDefaultTargetPlatformOverride = null;
  });
}
