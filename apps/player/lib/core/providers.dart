import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tihe_classroom/tihe_classroom.dart' as live;

import 'api/api_client.dart';
import 'api/models.dart';
import 'api/repositories.dart';
import 'security/device_identity.dart';
import 'security/token_store.dart';
import 'server.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final deviceIdentityProvider = Provider<DeviceIdentity>((ref) => DeviceIdentity());

/// The API client, rebuilt when the student changes the server address.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: ref.watch(serverProvider).apiBaseUrl,
    tokens: ref.watch(tokenStoreProvider),
  );
  client.onAuthenticationLost = () => ref.read(authControllerProvider.notifier).signedOut();
  return client;
});

/// A fresh access token for services/live, which verifies the same tokens as the API. Refreshed
/// through the API client when it is about to expire, so a class never starts with a stale one.
final accessTokenProvider = Provider<Future<String> Function()>((ref) {
  return () async {
    final tokens = ref.read(tokenStoreProvider);
    final fresh = await tokens.freshAccessToken();
    if (fresh != null) return fresh;
    // About to expire: any authenticated call refreshes it.
    await ref.read(authRepositoryProvider).me();
    return (await tokens.accessToken()) ?? '';
  };
});

/// The live classroom's API (services/live), at the same server.
final liveApiProvider = Provider<live.LiveApi>((ref) {
  final api = live.LiveApi(
    baseUrl: ref.watch(serverProvider).liveBaseUrl,
    accessToken: ref.watch(accessTokenProvider),
  );
  ref.onDispose(api.close);
  return api;
});

final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(apiClientProvider)));

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)),
);
final catalogRepositoryProvider = Provider(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);
final progressRepositoryProvider = Provider(
  (ref) => ProgressRepository(ref.watch(apiClientProvider)),
);
final playbackRepositoryProvider = Provider(
  (ref) => PlaybackRepository(ref.watch(apiClientProvider)),
);
final devicesRepositoryProvider = Provider(
  (ref) => DevicesRepository(ref.watch(apiClientProvider)),
);

/// Authentication state, which the router listens to.
sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.session);
  final Session session;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Resolved asynchronously; the router shows a splash while the state is unknown.
    Future.microtask(restore);
    return const AuthUnknown();
  }

  /// Restores a session on launch.
  ///
  /// A network failure here must not sign the student out: they may be on a plane with downloaded
  /// lectures, and offline playback has to keep working.
  Future<void> restore() async {
    final tokens = ref.read(tokenStoreProvider);
    if (!await tokens.hasSession()) {
      state = const AuthSignedOut();
      return;
    }
    try {
      state = AuthSignedIn(await ref.read(authRepositoryProvider).me());
    } catch (_) {
      state = const AuthSignedOut();
    }
  }

  void signedIn(Session session) => state = AuthSignedIn(session);

  /// After the student chose their own password: the session no longer needs one.
  Future<void> refreshSession() async {
    try {
      state = AuthSignedIn(await ref.read(authRepositoryProvider).me());
    } catch (_) {
      // The next request will find out; the current session stands.
    }
  }

  Future<void> signOut() async {
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {
      // A failed logout call still signs the user out locally; the server-side session expires.
    }
    await ref.read(tokenStoreProvider).clear();
    state = const AuthSignedOut();
  }

  /// Called by the API client when refresh fails irrecoverably.
  void signedOut() => state = const AuthSignedOut();
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

final coursesProvider = FutureProvider<List<Course>>(
  (ref) => ref.watch(catalogRepositoryProvider).courses(),
);

final courseProvider = FutureProvider.family<Course, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).course(id),
);

final devicesProvider = FutureProvider<List<Device>>(
  (ref) => ref.watch(devicesRepositoryProvider).list(),
);

/// Debounced search results.
///
/// Auto-disposed, so a query the student has typed past is dropped: without that, every
/// intermediate query ("مش", "مشت", …) kept its provider alive, its debounce timer still fired,
/// and a word cost one request per letter.
final searchProvider = FutureProvider.autoDispose.family<List<SearchHit>, String>((
  ref,
  query,
) async {
  if (query.trim().length < 2) return const [];
  var superseded = false;
  ref.onDispose(() => superseded = true);
  // Debounced here rather than in the widget so every caller gets it, and a superseded query
  // never reaches the server.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (superseded) return const [];
  return ref.watch(catalogRepositoryProvider).search(query);
});

/// The student's classes: live ones first, then upcoming by time, then the rest.
final liveClassesProvider = FutureProvider<List<live.LiveClass>>((ref) async {
  final classes = await ref.watch(liveApiProvider).listClasses();
  int rank(live.LiveClass c) => c.isLive ? 0 : (c.scheduledStartAt != null ? 1 : 2);
  return classes..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final at = a.scheduledStartAt, bt = b.scheduledStartAt;
    if (at != null && bt != null) return at.compareTo(bt);
    return a.title.compareTo(b.title);
  });
});

final instituteSettingsProvider = FutureProvider<InstituteSettings>(
  (ref) => ref.watch(adminRepositoryProvider).settings(),
);

final adminUsersProvider = FutureProvider.autoDispose.family<List<AdminUser>, String>((
  ref,
  query,
) async {
  // Debounced like search, so typing a number is one request, not one per digit.
  var superseded = false;
  ref.onDispose(() => superseded = true);
  if (query.isNotEmpty) await Future<void>.delayed(const Duration(milliseconds: 300));
  if (superseded) return const [];
  return ref.watch(adminRepositoryProvider).users(query: query);
});

final adminUserProvider = FutureProvider.autoDispose.family<AdminUserDetail, String>(
  (ref, id) => ref.watch(adminRepositoryProvider).user(id),
);

final adminCoursesProvider = FutureProvider.autoDispose<List<AdminCourse>>(
  (ref) => ref.watch(adminRepositoryProvider).courses(),
);
