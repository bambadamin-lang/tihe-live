import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/models.dart';
import 'api/repositories.dart';
import 'security/device_identity.dart';
import 'security/token_store.dart';

/// The API base URL.
///
/// Overridden at build time with `--dart-define=TIHE_API_URL=…`. The default points at a local
/// server so a fresh checkout runs against the development stack without configuration.
const apiBaseUrl = String.fromEnvironment(
  'TIHE_API_URL',
  defaultValue: 'http://localhost:3000/v1',
);

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final deviceIdentityProvider = Provider<DeviceIdentity>((ref) => DeviceIdentity());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(baseUrl: apiBaseUrl, tokens: ref.watch(tokenStoreProvider));
  client.onAuthenticationLost = () => ref.read(authControllerProvider.notifier).signedOut();
  return client;
});

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
final searchProvider = FutureProvider.family<List<SearchHit>, String>((ref, query) async {
  if (query.trim().length < 2) return const [];
  // Debounced here rather than in the widget so every caller gets it, and a cancelled query does not
  // reach the server at all.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  return ref.watch(catalogRepositoryProvider).search(query);
});
