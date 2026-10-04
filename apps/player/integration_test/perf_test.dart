import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tihe_player/core/api/models.dart';
import 'package:tihe_player/core/preferences.dart';
import 'package:tihe_player/core/providers.dart';
import 'package:tihe_player/core/router/app_router.dart';
import 'package:tihe_player/main.dart';

import '../test/support/fakes.dart';

/// Frame timings for the player app, in profile mode, on a desktop device:
///
///   flutter drive --profile -d windows \
///     --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
///
/// On a Linux CI box, generate a throwaway runner first (`flutter create --platforms=linux .`,
/// not committed) and prefix the command with `xvfb-run -s "-screen 0 1600x1000x24"`; timings
/// there come from a software renderer, so compare runs with each other, not with a device.
///
/// Each scenario writes `build/perf/NAME.timeline_summary.json` and the full timeline.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('player app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // A long library, so there is something to scroll.
    final courses = [
      for (var i = 0; i < 60; i++)
        Course(
          id: 'crs_$i',
          title: '${fakeCourses[i % 3].title} — گروه ${i + 1}',
          videoCount: 8 + i % 12,
          progress: (i % 7) / 6,
          policy: fakeCourse.policy,
          teacherName: fakeCourses[i % 3].teacherName,
        ),
    ];
    var loading = false;
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => FakeAuth(AuthSignedIn(fakeSession))),
        themeModeProvider.overrideWith(() => FixedThemeMode(ThemeMode.dark)),
        appVersionProvider.overrideWith((ref) async => '0.1.0'),
        catalogRepositoryProvider.overrideWithValue(FakeCatalog()),
        playbackRepositoryProvider.overrideWithValue(FakePlayback()),
        coursesProvider.overrideWith(
          (ref) => loading ? Future.delayed(const Duration(days: 1)) : Future.value(courses),
        ),
        courseProvider.overrideWith((ref, id) async => fakeCourse),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const TiheApp()),
    );
    final router = container.read(routerProvider);
    await Future<void>.delayed(const Duration(seconds: 2));

    // 1. The library, scrolled up and down.
    await binding.traceAction(() async {
      for (var i = 0; i < 3; i++) {
        await tester.fling(find.byType(CustomScrollView).first, const Offset(0, -900), 2500);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await tester.fling(find.byType(CustomScrollView).first, const Offset(0, 900), 2500);
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }, reportKey: 'library_scroll');

    // 2. Opening a course and going back.
    await binding.traceAction(() async {
      for (var i = 0; i < 3; i++) {
        router.push('/course/crs_1');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        router.pop();
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }, reportKey: 'navigate');

    // 3. The player, paused: controls up, the watermark drifting.
    router.push('/watch/vid_2');
    await Future<void>.delayed(const Duration(seconds: 2));
    await binding.traceAction(
      () => Future<void>.delayed(const Duration(seconds: 5)),
      reportKey: 'player_paused',
    );

    // 4. Playing: the controls fade out, only the watermark moves.
    await tester.tap(find.byTooltip('پخش').first);
    await Future<void>.delayed(const Duration(seconds: 1));
    await binding.traceAction(
      () => Future<void>.delayed(const Duration(seconds: 5)),
      reportKey: 'player_playing',
    );
    router.pop();
    await Future<void>.delayed(const Duration(seconds: 1));

    // 5. The library while it loads: skeletons pulsing.
    loading = true;
    container.invalidate(coursesProvider);
    router.go('/library');
    await Future<void>.delayed(const Duration(seconds: 1));
    await binding.traceAction(
      () => Future<void>.delayed(const Duration(seconds: 3)),
      reportKey: 'library_loading',
    );

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
