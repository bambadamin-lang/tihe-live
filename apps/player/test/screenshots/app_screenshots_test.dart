@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tihe_classroom/tihe_classroom.dart'
    show ClassroomFonts, WindowButtons, WindowChrome;
import 'package:tihe_player/core/api/models.dart';
import 'package:tihe_player/core/preferences.dart';
import 'package:tihe_player/core/providers.dart';
import 'package:tihe_player/core/router/app_router.dart';
import 'package:tihe_player/core/server.dart';
import 'package:tihe_player/core/theme/app_theme.dart';
import 'package:tihe_player/main.dart';

import '../support/fakes.dart';

/// Screenshots of the app for review, with the Windows frame drawn as the app draws it. Not a
/// regression test: they depend on the machine's font rendering, so they run only on request:
///
///   TIHE_SCREENSHOTS=1 flutter test test/screenshots --update-goldens
final _enabled = Platform.environment['TIHE_SCREENSHOTS'] == '1';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
    for (final family in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    ClassroomFonts.use(AppTheme.fontFamily);
    expect(await ClassroomFonts.ensureLoaded(), isTrue);
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    String location, {
    required Size size,
    TargetPlatform platform = TargetPlatform.windows,
    AuthState? auth,
    ThemeMode mode = ThemeMode.dark,
    bool frame = true,
  }) async {
    debugDisableShadows = false;
    debugDefaultTargetPlatformOverride = platform;
    try {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => FakeAuth(auth ?? AuthSignedIn(fakeSession))),
          themeModeProvider.overrideWith(() => FixedThemeMode(mode)),
          appVersionProvider.overrideWith((ref) async => '0.1.16'),
          catalogRepositoryProvider.overrideWithValue(FakeCatalog()),
          playbackRepositoryProvider.overrideWithValue(FakePlayback()),
          coursesProvider.overrideWith((ref) async => fakeCourses),
          courseProvider.overrideWith((ref, id) async => fakeCourse),
          devicesProvider.overrideWith((ref) async => fakeDevices),
          searchProvider.overrideWith((ref, query) async => FakeCatalog().search(query)),
          serverPingProvider.overrideWithValue((_) async => true),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TiheApp(
            frame: frame && platform == TargetPlatform.windows
                ? (page) => WindowChrome(
                    controls: WindowButtons(onMinimise: () {}, onMaximise: () {}, onClose: () {}),
                    dragArea: (bar) => bar,
                    child: page,
                  )
                : null,
          ),
        ),
      );
      await tester.pump();
      container.read(routerProvider).go(location);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await expectLater(find.byType(TiheApp), matchesGoldenFile('goldens/$name.png'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    } finally {
      debugDisableShadows = true;
      debugDefaultTargetPlatformOverride = null;
    }
  }

  const desktop = Size(1600, 900);
  const phone = Size(390, 844);

  testWidgets(
    'sign-in',
    (t) => shoot(t, 'sign-in', '/sign-in', size: desktop, auth: const AuthSignedOut()),
    skip: !_enabled,
  );
  testWidgets(
    'sign-in light',
    (t) => shoot(
      t,
      'sign-in-light',
      '/sign-in',
      size: desktop,
      auth: const AuthSignedOut(),
      mode: ThemeMode.light,
    ),
    skip: !_enabled,
  );
  testWidgets(
    'sign-in phone',
    (t) => shoot(
      t,
      'sign-in-phone',
      '/sign-in',
      size: phone,
      platform: TargetPlatform.android,
      auth: const AuthSignedOut(),
    ),
    skip: !_enabled,
  );
  testWidgets('home', (t) => shoot(t, 'home', '/home', size: desktop), skip: !_enabled);
  testWidgets('live', (t) => shoot(t, 'live', '/live', size: desktop), skip: !_enabled);
  testWidgets('library', (t) => shoot(t, 'library', '/library', size: desktop), skip: !_enabled);
  testWidgets('course', (t) => shoot(t, 'course', '/course/crs_1', size: desktop), skip: !_enabled);
  testWidgets('account', (t) => shoot(t, 'account', '/account', size: desktop), skip: !_enabled);
  testWidgets('watch', (t) => shoot(t, 'watch', '/watch/vid_2', size: desktop), skip: !_enabled);
  testWidgets(
    'change password',
    (t) => shoot(
      t,
      'change-password',
      '/change-password',
      size: desktop,
      auth: AuthSignedIn(
        Session(
          user: const AppUser(
            id: 'usr_1',
            phoneMasked: '0912•••6789',
            role: 'student',
            displayName: 'نیلوفر حسینی',
            mustChangePassword: true,
          ),
          device: fakeSession.device,
        ),
      ),
    ),
    skip: !_enabled,
  );
  testWidgets(
    'home phone',
    (t) => shoot(t, 'home-phone', '/home', size: phone, platform: TargetPlatform.android),
    skip: !_enabled,
  );
}
