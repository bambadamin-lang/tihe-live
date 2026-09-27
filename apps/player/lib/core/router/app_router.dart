import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/sign_in_screen.dart';
import '../../features/course/course_screen.dart';
import '../../features/devices/devices_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/player/player_screen.dart';
import '../providers.dart';

/// Routes, with a redirect that keeps signed-out users out of the library.
///
/// The redirect is the only place authentication gates navigation. Screens do not each check for a
/// session, because that is how one of them ends up forgetting.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AuthState>(const AuthUnknown());
  ref.listen(authControllerProvider, (_, next) => notifier.value = next, fireImmediately: true);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/library',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = notifier.value;

      // Session restore is still in flight; hold on the splash rather than flashing the sign-in
      // screen at a student who is already signed in.
      if (auth is AuthUnknown) return state.matchedLocation == '/' ? null : '/';

      final signedIn = auth is AuthSignedIn;
      final atSignIn = state.matchedLocation == '/sign-in';

      if (!signedIn && !atSignIn) return '/sign-in';
      if (signedIn && (atSignIn || state.matchedLocation == '/')) return '/library';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
      GoRoute(
        path: '/course/:id',
        builder: (_, state) => CourseScreen(courseId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/watch/:id',
        builder: (_, state) => PlayerScreen(videoId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/devices', builder: (_, __) => const DevicesScreen()),
    ],
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
