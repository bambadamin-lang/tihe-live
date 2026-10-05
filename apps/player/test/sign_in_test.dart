import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tihe_classroom/tihe_classroom.dart' hide ApiError;
import 'package:tihe_player/core/api/api_error.dart';
import 'package:tihe_player/core/api/models.dart';
import 'package:tihe_player/core/api/repositories.dart';
import 'package:tihe_player/core/preferences.dart';
import 'package:tihe_player/core/providers.dart';
import 'package:tihe_player/core/security/device_identity.dart';
import 'package:tihe_player/core/server.dart';
import 'package:tihe_player/main.dart';

import 'support/fakes.dart';

/// The welcome page: the classroom's own, so the app's front door is the design's (docs/11 §11),
/// with the sign-in and the server's address on it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _Auth auth;
  late List<String> pinged;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Future<bool> Function(String url)? ping,
    Widget Function(Widget page)? frame,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    pinged = [];
    auth = _Auth();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => FakeAuth(const AuthSignedOut())),
        themeModeProvider.overrideWith(() => FixedThemeMode(ThemeMode.dark)),
        appVersionProvider.overrideWith((ref) async => '0.1.0'),
        catalogRepositoryProvider.overrideWithValue(FakeCatalog()),
        coursesProvider.overrideWith((ref) async => fakeCourses),
        authRepositoryProvider.overrideWithValue(auth),
        deviceIdentityProvider.overrideWithValue(_Identity()),
        serverPingProvider.overrideWithValue((url) {
          pinged.add(url);
          return ping?.call(url) ?? Future.value(true);
        }),
      ],
    );
    addTearDown(container.dispose);
    auth.server = () => container.read(serverProvider).serverUrl;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TiheApp(frame: frame),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return container;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(WelcomeField, label),
    matching: find.byType(TextField),
  );

  testWidgets('the front door is the design\'s welcome page, with the glow cursor', (tester) async {
    await pump(tester);
    expect(find.byType(GlowCursorScope), findsOneWidget);
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.byType(BrandLockup), findsOneWidget);
    expect(find.byType(WelcomeCard), findsNWidgets(2));
    expect(find.byType(WelcomeField), findsNWidgets(3));
    expect(find.text('آنلاین'), findsOneWidget);
    expect(pinged.single, 'http://localhost:8080/v1');
    await finish(tester);
  });

  testWidgets('an unreachable server turns the lamp red; a new address is checked', (tester) async {
    await pump(tester, ping: (url) async => url.contains('tihe.ir'));
    expect(find.text('سرور در دسترس نیست'), findsOneWidget);

    await tester.enterText(field('نشانی سرور'), 'live.tihe.ir');
    await tester.pump(const Duration(seconds: 1));
    expect(pinged.last, 'http://live.tihe.ir/v1');
    expect(find.text('آنلاین'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('an address that cannot be one is refused before anything is sent', (tester) async {
    await pump(tester);
    await tester.enterText(field('نشانی سرور'), 'not an address');
    await tester.enterText(field('شماره موبایل'), '09123456789');
    await tester.enterText(field('رمز عبور'), 'secret-123');
    await tester.tap(find.widgetWithText(GlowButton, 'ورود'));
    await tester.pump();
    expect(find.text('این نشانی درست نیست.'), findsOneWidget);
    expect(auth.signedInAt, isEmpty);
    await finish(tester);
  });

  testWidgets('signs in on the address typed, and remembers it', (tester) async {
    final container = await pump(tester);
    await tester.enterText(field('نشانی سرور'), 'live.tihe.ir:8080');
    await tester.enterText(field('شماره موبایل'), '۰۹۱۲۳۴۵۶۷۸۹');
    await tester.enterText(field('رمز عبور'), 'secret-123');
    await tester.tap(find.widgetWithText(GlowButton, 'ورود'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(auth.signedInAt, ['http://live.tihe.ir:8080']);
    // As the API takes it, whatever digits were typed.
    expect(auth.phones, ['+989123456789']);
    expect(container.read(serverProvider).serverUrl, 'http://live.tihe.ir:8080');
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
    await finish(tester);
  });

  testWidgets('the server\'s refusal shows in the card, in its own words', (tester) async {
    await pump(tester);
    auth.refusal = const ApiError(
      code: 'INVALID_CREDENTIALS',
      message: 'Phone or password is wrong',
      messageFa: 'شماره یا رمز درست نیست',
    );
    await tester.enterText(field('شماره موبایل'), '09123456789');
    await tester.enterText(field('رمز عبور'), 'wrong-one');
    await tester.tap(find.widgetWithText(GlowButton, 'ورود'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.widgetWithText(WelcomeNote, 'شماره یا رمز درست نیست'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the demo card opens the class as the chosen role', (tester) async {
    await pump(tester);
    await tester.tap(find.text('دانشجو'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(GlowButton, 'ورود به کلاس نمایشی'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ClassroomPage), findsOneWidget);
    // A student: the hand, not the end of class.
    expect(find.byType(HandToggle), findsOneWidget);
    await finish(tester);
  });

  testWidgets('where the app draws its own frame, the welcome page carries the window buttons', (
    tester,
  ) async {
    await pump(
      tester,
      frame: (page) => WindowChrome(
        controls: WindowButtons(onMinimise: () {}, onMaximise: () {}, onClose: () {}),
        dragArea: (bar) => bar,
        child: page,
      ),
    );
    expect(
      find.descendant(of: find.byType(WelcomeTitleBar), matching: find.byType(WindowButtons)),
      findsOneWidget,
    );
    await finish(tester);
  });
}

class _Auth extends Fake implements AuthRepository {
  late String Function() server;
  final signedInAt = <String>[];
  final phones = <String>[];
  ApiError? refusal;

  @override
  Future<Session> login({
    required String phone,
    required String password,
    required Map<String, dynamic> device,
  }) async {
    if (refusal case final refusal?) throw refusal;
    signedInAt.add(server());
    phones.add(phone);
    return fakeSession;
  }
}

class _Identity extends Fake implements DeviceIdentity {
  @override
  Future<Map<String, dynamic>> describe() async => {'name': 'Test PC', 'platform': 'windows'};
}
