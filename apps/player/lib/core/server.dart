import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'security/app_log.dart';

/// Where the institute's server is.
///
/// One address serves both halves: the API at `/v1` and the live classroom at `/v1/live`, behind
/// the server's gateway (infra/docker/compose.server.yml). Development builds can point each at its
/// own port with `--dart-define=TIHE_API_URL=…` and `TIHE_LIVE_URL=…`.
class ServerConfig {
  const ServerConfig(this.serverUrl);

  /// e.g. `http://192.168.1.10:8080`, without a trailing slash.
  final String serverUrl;

  static const _apiOverride = String.fromEnvironment('TIHE_API_URL');
  static const _liveOverride = String.fromEnvironment('TIHE_LIVE_URL');

  String get apiBaseUrl => _apiOverride.isNotEmpty ? _apiOverride : '$serverUrl/v1';
  String get liveBaseUrl => _liveOverride.isNotEmpty ? _liveOverride : '$serverUrl/v1/live';

  /// What the student typed, made into an address, or null if it cannot be one. Accepts what people
  /// actually type: no scheme, a trailing slash, Persian digits.
  static String? normalize(String input) {
    var text = input
        .trim()
        .replaceAllMapped(RegExp('[۰-۹]'), (m) => '${m[0]!.codeUnitAt(0) - 0x06f0}')
        .replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}');
    if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // An address pasted from the old classroom app or a browser: keep the server, drop the path.
    final origin = uri.hasPort
        ? '${uri.scheme}://${uri.host}:${uri.port}'
        : '${uri.scheme}://${uri.host}';
    return origin;
  }
}

/// The server address: the student's own choice, else what the installer was given, else the
/// build's default.
class ServerController extends Notifier<ServerConfig> {
  static const _key = 'server.url';
  static const _buildDefault = String.fromEnvironment(
    'TIHE_SERVER_URL',
    defaultValue: 'http://localhost:8080',
  );

  @override
  ServerConfig build() {
    Future.microtask(_restore);
    return ServerConfig(installedServerUrl() ?? _buildDefault);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = ServerConfig.normalize(prefs.getString(_key) ?? '');
      if (stored != null && stored != state.serverUrl) state = ServerConfig(stored);
    } catch (error) {
      AppLog.warn('server address not restored: $error');
    }
  }

  /// Saves a new address. False when it cannot be an address.
  Future<bool> set(String input) async {
    final url = ServerConfig.normalize(input);
    if (url == null) return false;
    state = ServerConfig(url);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, url);
    } catch (error) {
      AppLog.warn('server address not saved: $error');
    }
    return true;
  }
}

final serverProvider = NotifierProvider<ServerController, ServerConfig>(ServerController.new);

/// The address the Windows installer wrote next to the executable (installer/windows), so a
/// student never has to type it. Reads the old classroom app's `liveApiBaseUrl` too.
String? installedServerUrl() {
  try {
    final file = File(
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}tihe_live.json',
    );
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map) return null;
    final value = json['serverUrl'] ?? json['liveApiBaseUrl'];
    return value is String ? ServerConfig.normalize(value) : null;
  } on Object {
    // A damaged file only costs the pre-filled address.
    return null;
  }
}
