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

  Future<Json> _call(String method, String path) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['authorization'] = 'Bearer ${await accessToken()}'
      ..headers['accept'] = 'application/json';
    final response = await http.Response.fromStream(
      await _http.send(request).timeout(const Duration(seconds: 15)),
    );
    final body = response.body.isEmpty
        ? <String, Object?>{}
        : asJson(jsonDecode(response.body));
    if (response.statusCode >= 400) {
      throw ApiError.fromJson(response.statusCode, body);
    }
    return body;
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
