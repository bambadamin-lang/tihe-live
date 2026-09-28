import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores access and refresh tokens in the OS-backed secure store.
///
/// **What is not here: content keys.** Those never enter Dart at all — they are unwrapped inside
/// `packages/secure-core` (Rust) using a device private key sealed in Android Keystore or Windows
/// DPAPI, and held in locked memory. See docs/03-content-protection.md.
///
/// Tokens are a lesser secret: they expire, they are revocable server-side, and stealing one does
/// not decrypt a single video.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'tihe.access_token';
  static const _refreshKey = 'tihe.refresh_token';
  static const _accessExpiryKey = 'tihe.access_expires_at';

  /// Cached in memory so the hot path does not hit the platform keystore on every request.
  String? _cachedAccess;
  DateTime? _cachedExpiry;

  Future<String?> accessToken() async {
    if (_cachedAccess != null && _cachedExpiry != null) {
      // Treated as expired slightly early, so a request does not start with a token that expires
      // while it is in flight.
      if (DateTime.now().isBefore(_cachedExpiry!.subtract(const Duration(seconds: 30)))) {
        return _cachedAccess;
      }
    }

    final token = await _storage.read(key: _accessKey);
    final expiry = await _storage.read(key: _accessExpiryKey);
    _cachedAccess = token;
    _cachedExpiry = expiry == null ? null : DateTime.tryParse(expiry);
    return token;
  }

  Future<String?> refreshToken() => _storage.read(key: _refreshKey);

  /// Persists a token pair from an auth or refresh response.
  Future<void> save(Map<String, dynamic> response) async {
    // Both shapes appear: sign-in nests tokens under `tokens`, refresh returns them at the top level.
    final tokens = (response['tokens'] as Map<String, dynamic>?) ?? response;

    final access = tokens['accessToken'] as String?;
    final refresh = tokens['refreshToken'] as String?;
    final expiresAt = tokens['accessExpiresAt'] as String?;

    if (access == null || refresh == null) return;

    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
    if (expiresAt != null) {
      await _storage.write(key: _accessExpiryKey, value: expiresAt);
    }

    _cachedAccess = access;
    _cachedExpiry = expiresAt == null ? null : DateTime.tryParse(expiresAt);
  }

  Future<bool> hasSession() async => (await _storage.read(key: _refreshKey)) != null;

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _accessExpiryKey);
    _cachedAccess = null;
    _cachedExpiry = null;
  }
}
