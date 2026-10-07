import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../contracts.dart';

/// The REST side of services/live (`/v1/live`). Every failure arrives as [ApiError] carrying
/// the server's Persian message, so the UI never maps error codes itself.
class LiveApi {
  LiveApi({
    required this.baseUrl,
    required this.accessToken,
    http.Client? client,
  }) : _http = client ?? http.Client();

  /// e.g. `https://api.tihe.ir/v1/live`.
  final String baseUrl;

  /// The services/api access token, fetched fresh for each call (it rotates every 15 min).
  final Future<String> Function() accessToken;
  final http.Client _http;

  /// How long one request may take before it counts as no connection.
  static const timeout = Duration(seconds: 15);

  /// Sends one request and decodes its body. Transport failures and bodies that are not the
  /// error envelope (a proxy's HTML error page, a cut-off response) become [ApiError] too, with
  /// a Persian message, so callers handle exactly one exception type.
  Future<Object?> _send(String method, String path) async {
    // Outside the try: a failure to get a token is the token source's own error to report.
    final token = await accessToken();
    final http.Response response;
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers['authorization'] = 'Bearer $token'
        ..headers['accept'] = 'application/json';
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on http.ClientException {
      throw ApiError.network();
    } on TimeoutException {
      throw ApiError.network();
    }
    Object? body;
    try {
      body = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (response.statusCode >= 400) {
      final envelope = body is Map<String, Object?> ? body['error'] : null;
      if (envelope is Map<String, Object?> &&
          envelope['code'] is String &&
          envelope['messageFa'] is String) {
        throw ApiError.fromJson(response.statusCode, body as Json);
      }
      throw ApiError.unexpected(response.statusCode);
    }
    return body;
  }

  Future<Json> _call(String method, String path) async {
    final body = await _send(method, path);
    if (body is! Map) throw ApiError.unexpected(200);
    return asJson(body);
  }

  /// The caller's classes: those of every course they attend or teach (all of them for admins).
  Future<List<LiveClass>> listClasses() async {
    final body = await _send('GET', '/classes');
    if (body is! List) throw ApiError.unexpected(200);
    return [for (final c in body) LiveClass.fromJson(asJson(c))];
  }

  /// Enter a class: LiveKit token, gateway ticket, watermark and capture policy.
  Future<JoinResponse> join(String sessionId) async =>
      JoinResponse.fromJson(await _call('POST', '/sessions/$sessionId/join'));

  /// Start a class now (host). Returns the live session, or the one already running.
  Future<LiveSession> start(String classId) async =>
      LiveSession.fromJson(await _call('POST', '/classes/$classId/sessions'));

  Future<LiveSession> end(String sessionId) async =>
      LiveSession.fromJson(await _call('POST', '/sessions/$sessionId/end'));

  Future<LiveSession> startRecording(String sessionId) async =>
      LiveSession.fromJson(
        await _call('POST', '/sessions/$sessionId/recording/start'),
      );

  void close() => _http.close();

  /// Whether services/live answers at [baseUrl] — its health check needs no token. For a
  /// launcher's status lamp; any failure, including a slow answer, counts as unreachable.
  static Future<bool> reachable(String baseUrl, {http.Client? client}) async {
    final uri = Uri.tryParse('${baseUrl.trim()}/health');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(uri, headers: {'accept': 'application/json'})
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } on Object {
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }
}
