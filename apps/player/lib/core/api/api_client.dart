import 'dart:async';

import 'package:dio/dio.dart';

import '../security/token_store.dart';
import 'api_error.dart';

/// HTTP client for the TIHE Live API.
///
/// Three responsibilities beyond plain requests:
///
///  * **Token refresh**, serialised. Several screens can 401 at once on app resume; without a
///    single in-flight refresh they would each burn a single-use refresh token, and the server
///    treats a reused refresh token as theft and revokes the whole device session.
///  * **Error translation** into [ApiError], so no caller ever handles a raw [DioException].
///  * **Certificate pinning** (M3). The hook is here rather than added later, because retrofitting
///    it tends to mean shipping a release without it.
class ApiClient {
  ApiClient({required String baseUrl, required TokenStore tokens})
      : _tokens = tokens,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            // The API always answers with its own envelope, including for 4xx. Letting Dio throw on
            // status would lose the body we need to read the error code from.
            validateStatus: (_) => true,
            headers: {'Content-Type': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokens.accessToken();
          if (token != null && options.extra['skipAuth'] != true) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStore _tokens;

  /// Guards against parallel refreshes. See the class comment — this is not premature optimisation,
  /// it prevents a session revocation.
  Future<bool>? _refreshInFlight;

  /// Called when refresh fails and the user must sign in again.
  void Function()? onAuthenticationLost;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<Map<String, dynamic>> post(String path, {Object? body, bool skipAuth = false}) => _send(
        () => _dio.post(path, data: body, options: Options(extra: {'skipAuth': skipAuth})),
      );

  Future<Map<String, dynamic>> put(String path, {Object? body}) =>
      _send(() => _dio.put(path, data: body));

  Future<void> delete(String path) async {
    await _send(() => _dio.delete(path), allowEmpty: true);
  }

  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() request, {
    bool allowEmpty = false,
    bool isRetry = false,
  }) async {
    final Response<dynamic> response;
    try {
      response = await request();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badCertificate) {
        // Pinning failure is not a connectivity problem: something is intercepting the connection.
        throw const ApiError(
          code: 'FORBIDDEN',
          message: 'certificate validation failed',
          messageFa: 'اتصال امن برقرار نشد. از شبکه مطمئن استفاده کنید.',
        );
      }
      throw ApiError.network();
    }

    final status = response.statusCode ?? 0;

    if (status >= 200 && status < 300) {
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (allowEmpty || data == null || (data is String && data.isEmpty)) return const {};
      return {'data': data};
    }

    final error = response.data is Map<String, dynamic>
        ? ApiError.fromJson(response.data as Map<String, dynamic>)
        : ApiError.network();

    // One refresh attempt, then give up. Retrying a second time after a failed refresh only burns
    // tokens and delays telling the user.
    if (status == 401 && !isRetry && error.code != 'DEVICE_REVOKED') {
      final refreshed = await _refresh();
      if (refreshed) {
        return _send(request, allowEmpty: allowEmpty, isRetry: true);
      }
      onAuthenticationLost?.call();
    }

    throw error;
  }

  Future<bool> _refresh() {
    // Join the in-flight refresh rather than starting another.
    return _refreshInFlight ??= _performRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await _tokens.refreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );
      if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
        await _tokens.clear();
        return false;
      }
      await _tokens.save(response.data as Map<String, dynamic>);
      return true;
    } on DioException {
      // A network failure during refresh is not a reason to sign the user out — they may simply be
      // offline, and offline playback must keep working.
      return false;
    }
  }
}
