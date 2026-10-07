import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_screen.dart';
import '../../features/admin/admin_screen.dart';
import '../../features/admin/admin_user_screen.dart';
import '../../features/auth/change_password_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/live/live_screen.dart';
import '../../features/course/course_screen.dart';
import '../../features/devices/devices_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/player/player_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/shell/app_shell.dart';
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
    initialLocation: '/home',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = notifier.value;

      // Session restore is still in flight; hold on the splash rather than flashing the sign-in
      // screen at a student who is already signed in.
      if (auth is AuthUnknown) return state.matchedLocation == '/' ? null : '/';

      final at = state.matchedLocation;
      if (auth is! AuthSignedIn) return at == '/sign-in' ? null : '/sign-in';

      final user = auth.session.user;
      // A password the institute set must be replaced before anything else.
      if (user.mustChangePassword) return at == '/change-password' ? null : '/change-password';
      if (at == '/sign-in' || at == '/' || at == '/change-password') return '/home';
      if (at.startsWith('/admin') && !user.isAdmin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(
        path: '/change-password',
        builder: (_, __) => const ChangePasswordScreen(forced: true),
      ),

      // Everything signed-in sits in the shell (sidebar, rail or bottom bar), except the player.
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/live', builder: (_, __) => const LiveScreen()),
          GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
          GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
          GoRoute(
            path: '/course/:id',
            builder: (_, state) => CourseScreen(courseId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/devices', builder: (_, __) => const DevicesScreen()),
          GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
          GoRoute(path: '/account/password', builder: (_, __) => const ChangePasswordScreen()),
          GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
          GoRoute(
            path: '/admin/users/:id',
            builder: (_, state) => AdminUserScreen(userId: state.pathParameters['id']!),
          ),
        ],
      ),

      // Full-bleed: the lecture gets the whole window.
      GoRoute(
        path: '/watch/:id',
        // Keyed by video, so previous/next always builds a fresh screen and a fresh playback session.
        builder: (_, state) => PlayerScreen(
          key: ValueKey(state.pathParameters['id']),
          videoId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});
