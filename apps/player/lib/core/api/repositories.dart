import '../security/app_log.dart';
import '../security/token_store.dart';
import 'api_client.dart';
import 'models.dart';

/// Sign-in and session management.
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  /// Requests an SMS code.
  ///
  /// Returns the dev code when the server is running with the console SMS driver, so local
  /// development needs no SMS gateway. In production this is always null.
  Future<({String requestId, int resendAfterSeconds, String? devCode})> requestOtp(
    String phone,
  ) async {
    final json = await _api.post('/auth/otp/request', body: {'phone': phone}, skipAuth: true);
    AppLog.info('OTP requested for ${AppLog.maskPhone(phone)}');
    return (
      requestId: json['requestId'] as String,
      resendAfterSeconds: json['resendAfterSeconds'] as int? ?? 60,
      devCode: json['devCode'] as String?,
    );
  }

  /// Verifies a code and registers this device.
  ///
  /// The caller must pass the device descriptor from [DeviceIdentity]; the server registers it on
  /// first sight so a student is never signed in but unable to play anything.
  Future<Session> verifyOtp({
    required String phone,
    required String code,
    required Map<String, dynamic> device,
  }) async {
    final json = await _api.post(
      '/auth/otp/verify',
      body: {'phone': phone, 'code': code, 'device': device},
      skipAuth: true,
    );

    // Persisted here rather than by the caller: a screen that forgets leaves the student
    // authenticated for exactly one request, and the bug looks like a random session loss.
    await _tokens.save(json);

    return Session.fromJson(json);
  }

  Future<Session> me() async {
    final json = await _api.get('/auth/me');
    return Session.fromJson(json);
  }

  Future<void> logout() => _api.post('/auth/logout');
}

/// The student's library.
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  Future<List<Course>> courses() async {
    final json = await _api.get('/catalog/courses');
    return (json['items'] as List<dynamic>)
        .map((c) => Course.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<Course> course(String id) async {
    final json = await _api.get('/catalog/courses/$id');
    return Course.fromJson(json);
  }

  Future<Video> video(String id) async {
    final json = await _api.get('/catalog/videos/$id');
    return Video.fromJson(json);
  }

  /// Persian-aware search. Normalisation happens server-side, so the query is sent as typed —
  /// Arabic letter forms, Persian digits and all.
  Future<List<SearchHit>> search(String query, {String? courseId}) async {
    final json = await _api.get(
      '/catalog/search',
      query: {'q': query, if (courseId != null) 'courseId': courseId},
    );
    return (json['items'] as List<dynamic>)
        .map((h) => SearchHit.fromJson(h as Map<String, dynamic>))
        .toList();
  }
}

/// Watch progress and the offline event queue.
class ProgressRepository {
  ProgressRepository(this._api);

  final ApiClient _api;

  Future<Duration> position(String videoId) async {
    final json = await _api.get('/progress/$videoId');
    return Duration(milliseconds: json['positionMs'] as int? ?? 0);
  }

  Future<void> save(String videoId, Duration position, {bool? completed}) async {
    await _api.put(
      '/progress/$videoId',
      body: {
        'positionMs': position.inMilliseconds,
        if (completed != null) 'completed': completed,
      },
    );
  }

  /// Submits watch events, including a backlog recorded offline.
  ///
  /// Client timestamps are preserved server-side, so statistics reflect when a student actually
  /// watched rather than when their device next found a network. Returns the current revocation
  /// epoch, which is how a device that was offline during a revocation finds out.
  Future<int> submitEvents(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return 0;
    final json = await _api.post('/progress/events', body: {'events': events});
    return json['revocationEpoch'] as int? ?? 0;
  }
}

/// Protected playback sessions.
class PlaybackRepository {
  PlaybackRepository(this._api);

  final ApiClient _api;

  /// Mints a playback session.
  ///
  /// [environment] reports what the client observed about itself — a screen recorder, a virtual
  /// display, an emulator. A patched client can lie, which is why the OS-level capture blocking
  /// exists; this stops the honest majority cheaply and flags patterns worth investigating.
  Future<PlaybackSession> start({
    required String videoId,
    required String deviceId,
    Map<String, bool>? environment,
  }) async {
    final json = await _api.post(
      '/playback/$videoId/session',
      body: {'deviceId': deviceId, if (environment != null) 'environment': environment},
    );
    return PlaybackSession.fromJson(json);
  }

  /// Keeps the session alive and checks for revocation.
  ///
  /// Returns whether playback must stop. This is what bounds revocation latency to one heartbeat:
  /// the server cannot push to a device, so the device asks.
  Future<({bool stop, String? reason, int revocationEpoch})> heartbeat(
    String sessionId,
    Duration position,
  ) async {
    final json = await _api.post(
      '/playback/sessions/$sessionId/heartbeat',
      body: {'positionMs': position.inMilliseconds},
    );
    return (
      stop: json['stop'] as bool? ?? false,
      reason: json['stopReason'] as String?,
      revocationEpoch: json['revocationEpoch'] as int? ?? 0,
    );
  }

  Future<void> end(String sessionId) => _api.delete('/playback/sessions/$sessionId');
}

/// Device management.
class DevicesRepository {
  DevicesRepository(this._api);

  final ApiClient _api;

  Future<List<Device>> list() async {
    final json = await _api.get('/devices');
    return (json['items'] as List<dynamic>)
        .map((d) => Device.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  /// Releases a device. The server also expires that device's downloads — a released machine must
  /// not keep playing what it already holds.
  Future<void> release(String deviceId) => _api.delete('/devices/$deviceId');
}
