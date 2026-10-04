import '../security/app_log.dart';
import '../security/token_store.dart';
import 'api_client.dart';
import 'api_error.dart';
import 'models.dart';

/// Sign-in refused because the account already has its limit of devices signed in.
class DeviceLimitReached implements Exception {
  const DeviceLimitReached(this.limit, this.messageFa);

  final DeviceLimit limit;
  final String messageFa;
}

/// Sign-in and session management (ADR-0013, ADR-0014).
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  /// Signs in with phone and password and registers this device.
  ///
  /// Throws [DeviceLimitReached] when the account is signed in on its limit of devices: the
  /// student picks one to sign out ([replaceDevice]) instead of hitting a dead end.
  Future<Session> login({
    required String phone,
    required String password,
    required Map<String, dynamic> device,
  }) async {
    final json = await _guardLimit(
      () => _api.post(
        '/auth/login',
        body: {'phone': phone, 'password': password, 'device': device},
        skipAuth: true,
      ),
    );
    AppLog.info('signed in as ${AppLog.maskPhone(phone)}');
    return _persist(json);
  }

  /// Signs [signOutDeviceId] out and finishes the sign-in that hit the limit.
  Future<Session> replaceDevice({
    required String ticket,
    required String signOutDeviceId,
    required Map<String, dynamic> device,
  }) async {
    final json = await _guardLimit(
      () => _api.post(
        '/auth/login/replace',
        body: {'ticket': ticket, 'signOutDeviceId': signOutDeviceId, 'device': device},
        skipAuth: true,
      ),
    );
    return _persist(json);
  }

  Future<void> changePassword({
    required String current,
    required String next,
    bool signOutOtherDevices = true,
  }) async {
    await _api.post(
      '/auth/password',
      body: {
        'currentPassword': current,
        'newPassword': next,
        'signOutOtherDevices': signOutOtherDevices,
      },
    );
  }

  Future<Session> me() async {
    final json = await _api.get('/auth/me');
    return Session.fromJson(json);
  }

  Future<void> logout() => _api.post('/auth/logout');

  Future<Map<String, dynamic>> _guardLimit(Future<Map<String, dynamic>> Function() call) async {
    try {
      return await call();
    } on ApiError catch (e) {
      if (e.code == 'DEVICE_LIMIT_REACHED' && e.details != null) {
        throw DeviceLimitReached(DeviceLimit.fromDetails(e.details!), e.messageFa);
      }
      rethrow;
    }
  }

  /// Persisted here rather than by the caller: a screen that forgets leaves the student
  /// authenticated for exactly one request, and the bug looks like a random session loss.
  Future<Session> _persist(Map<String, dynamic> json) async {
    await _tokens.save(json);
    return Session.fromJson(json);
  }
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
      body: {'positionMs': position.inMilliseconds, if (completed != null) 'completed': completed},
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

  /// Signs a device out, which frees its slot. The server also expires that device's downloads —
  /// a signed-out machine must not keep playing what it already holds.
  Future<void> signOut(String deviceId) => _api.delete('/devices/$deviceId');
}

/// Accounts, the device limit and enrollments, for admins.
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  Future<InstituteSettings> settings() async =>
      InstituteSettings.fromJson(await _api.get('/admin/settings'));

  Future<InstituteSettings> setDefaultMaxDevices(int value) async => InstituteSettings.fromJson(
    await _api.patch('/admin/settings', body: {'defaultMaxDevices': value}),
  );

  Future<List<AdminUser>> users({String? query}) async {
    final json = await _api.get(
      '/admin/users',
      query: {if (query != null && query.trim().isNotEmpty) 'query': query.trim()},
    );
    return (json['items'] as List<dynamic>)
        .map((u) => AdminUser.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  Future<AdminUserDetail> user(String id) async =>
      AdminUserDetail.fromJson(await _api.get('/admin/users/$id'));

  Future<AdminUserDetail> createUser({
    required String phone,
    required String displayName,
    required String password,
    String role = 'student',
    bool mustChangePassword = true,
    int? maxDevices,
  }) async => AdminUserDetail.fromJson(
    await _api.post(
      '/admin/users',
      body: {
        'phone': phone,
        'displayName': displayName,
        'password': password,
        'role': role,
        'mustChangePassword': mustChangePassword,
        'maxDevices': maxDevices,
      },
    ),
  );

  /// Only the fields given change. Pass `clearMaxDevices` to return to the institute default.
  Future<AdminUserDetail> updateUser(
    String id, {
    String? displayName,
    String? role,
    String? status,
    int? maxDevices,
    bool clearMaxDevices = false,
    String? password,
    bool? mustChangePassword,
  }) async => AdminUserDetail.fromJson(
    await _api.patch(
      '/admin/users/$id',
      body: {
        if (displayName != null) 'displayName': displayName,
        if (role != null) 'role': role,
        if (status != null) 'status': status,
        if (maxDevices != null) 'maxDevices': maxDevices,
        if (clearMaxDevices) 'maxDevices': null,
        if (password != null) 'password': password,
        if (mustChangePassword != null) 'mustChangePassword': mustChangePassword,
      },
    ),
  );

  Future<void> signOutDevice(String userId, String deviceId) =>
      _api.delete('/admin/users/$userId/devices/$deviceId');

  Future<AdminUserDetail> enroll(String userId, String courseId) async => AdminUserDetail.fromJson(
    await _api.post('/admin/users/$userId/enrollments', body: {'courseId': courseId}),
  );

  Future<AdminUserDetail> unenroll(String userId, String courseId) async {
    await _api.delete('/admin/users/$userId/enrollments/$courseId');
    return user(userId);
  }

  Future<List<AdminCourse>> courses() async => (await _api.getList(
    '/admin/courses',
  )).map((c) => AdminCourse.fromJson(c as Map<String, dynamic>)).toList();
}
