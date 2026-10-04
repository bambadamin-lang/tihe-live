import 'gateway.dart';
import 'json.dart';
import 'roles.dart';

/// The REST side of services/live that the classroom calls — packages/contracts/src/live/
/// endpoints.ts. Only what the client needs is mirrored.
/// A class as listed for its students and teacher (liveClassSchema in packages/contracts).
/// Only what the app shows: the classroom itself gets everything else at join.
class LiveClass {
  const LiveClass({
    required this.id,
    required this.courseId,
    required this.title,
    required this.description,
    required this.teacherId,
    required this.scheduledStartAt,
    required this.durationMinutes,
    required this.liveSessionId,
  });

  factory LiveClass.fromJson(Json j) => LiveClass(
    id: j['id'] as String,
    courseId: j['courseId'] as String,
    title: j['title'] as String,
    description: j['description'] as String?,
    teacherId: j['teacherId'] as String,
    scheduledStartAt: switch (j['scheduledStartAt']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
    durationMinutes: j['durationMinutes'] as int,
    liveSessionId: j['liveSessionId'] as String?,
  );

  final String id;
  final String courseId;
  final String title;
  final String? description;
  final String teacherId;

  /// UTC; null when the class has no fixed time.
  final DateTime? scheduledStartAt;
  final int durationMinutes;

  /// The session to join while the class is live; null otherwise.
  final String? liveSessionId;

  bool get isLive => liveSessionId != null;
}

class LiveSession {
  const LiveSession({
    required this.id,
    required this.classId,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.recording,
  });

  factory LiveSession.fromJson(Json j) => LiveSession(
    id: j['id'] as String,
    classId: j['classId'] as String,
    status: j['status'] as String,
    startedAt: j['startedAt'] as String,
    endedAt: j['endedAt'] as String?,
    recording: RecordingState.fromJson(asJson(j['recording'])),
  );

  final String id;
  final String classId;

  /// `live` or `ended`.
  final String status;
  final String startedAt;
  final String? endedAt;
  final RecordingState recording;

  Json toJson() => {
    'id': id,
    'classId': classId,
    'status': status,
    'startedAt': startedAt,
    'endedAt': endedAt,
    'recording': recording.toJson(),
  };
}

/// Parameters of this user's own watermark (watermarkSchema in the contract).
class WatermarkSpec {
  const WatermarkSpec({
    required this.text,
    required this.opacity,
    required this.fontSize,
    required this.movement,
    required this.periodSeconds,
    required this.seed,
  });

  factory WatermarkSpec.fromJson(Json j) => WatermarkSpec(
    text: j['text'] as String,
    opacity: (j['opacity'] as num).toDouble(),
    fontSize: j['fontSize'] as int,
    movement: j['movement'] as String,
    periodSeconds: j['periodSeconds'] as int,
    seed: j['seed'] as int,
  );

  /// Masked phone and short id, e.g. `0912•••6789 · #48213`. The time is added when drawn.
  final String text;
  final double opacity;
  final int fontSize;

  /// `corners` in the classroom.
  final String movement;
  final int periodSeconds;
  final int seed;

  Json toJson() => {
    'text': text,
    'opacity': opacity,
    'fontSize': fontSize,
    'movement': movement,
    'periodSeconds': periodSeconds,
    'seed': seed,
  };
}

class CapturePolicySpec {
  const CapturePolicySpec({
    required this.block,
    required this.windowsAffinity,
    required this.censorAudio,
    required this.reportToHost,
    required this.recorderProcessesWindows,
    required this.recorderProcessesMacos,
    required this.iosSecureLayer,
    required this.scanIntervalMs,
  });

  factory CapturePolicySpec.fromJson(Json j) {
    final processes = asJson(j['recorderProcesses']);
    return CapturePolicySpec(
      block: j['block'] as bool,
      windowsAffinity: j['windowsAffinity'] as String,
      censorAudio: j['censorAudio'] as bool,
      reportToHost: j['reportToHost'] as bool,
      recorderProcessesWindows: listOf<String>(processes['windows']),
      recorderProcessesMacos: listOf<String>(processes['macos']),
      iosSecureLayer: j['iosSecureLayer'] as bool,
      scanIntervalMs: j['scanIntervalMs'] as int,
    );
  }

  final bool block;

  /// `monitor` or `exclude`.
  final String windowsAffinity;
  final bool censorAudio;
  final bool reportToHost;
  final List<String> recorderProcessesWindows;
  final List<String> recorderProcessesMacos;
  final bool iosSecureLayer;
  final int scanIntervalMs;

  Json toJson() => {
    'block': block,
    'windowsAffinity': windowsAffinity,
    'censorAudio': censorAudio,
    'reportToHost': reportToHost,
    'recorderProcesses': {
      'windows': recorderProcessesWindows,
      'macos': recorderProcessesMacos,
    },
    'iosSecureLayer': iosSecureLayer,
    'scanIntervalMs': scanIntervalMs,
  };
}

/// Everything needed to enter a class, from `POST /v1/live/sessions/:id/join`.
class JoinResponse {
  const JoinResponse({
    required this.session,
    required this.classTitle,
    required this.userId,
    required this.name,
    required this.role,
    required this.livekitUrl,
    required this.livekitToken,
    required this.gatewayUrl,
    required this.ticket,
    required this.ticketExpiresAt,
    required this.watermark,
    required this.capturePolicy,
  });

  factory JoinResponse.fromJson(Json j) {
    final you = asJson(j['you']);
    final livekit = asJson(j['livekit']);
    final gateway = asJson(j['gateway']);
    return JoinResponse(
      session: LiveSession.fromJson(asJson(j['session'])),
      classTitle: j['classTitle'] as String,
      userId: you['userId'] as String,
      name: you['name'] as String,
      role: ClassRole.fromWire(you['role']),
      livekitUrl: livekit['url'] as String,
      livekitToken: livekit['token'] as String,
      gatewayUrl: gateway['url'] as String,
      ticket: gateway['ticket'] as String,
      ticketExpiresAt: gateway['ticketExpiresAt'] as String,
      watermark: WatermarkSpec.fromJson(asJson(j['watermark'])),
      capturePolicy: CapturePolicySpec.fromJson(asJson(j['capturePolicy'])),
    );
  }

  final LiveSession session;
  final String classTitle;
  final String userId;
  final String name;
  final ClassRole role;
  final String livekitUrl;
  final String livekitToken;
  final String gatewayUrl;
  final String ticket;
  final String ticketExpiresAt;
  final WatermarkSpec watermark;
  final CapturePolicySpec capturePolicy;

  Json toJson() => {
    'session': session.toJson(),
    'classTitle': classTitle,
    'you': {'userId': userId, 'name': name, 'role': role.wire},
    'livekit': {'url': livekitUrl, 'token': livekitToken},
    'gateway': {
      'url': gatewayUrl,
      'ticket': ticket,
      'ticketExpiresAt': ticketExpiresAt,
    },
    'watermark': watermark.toJson(),
    'capturePolicy': capturePolicy.toJson(),
  };
}

/// The shared error envelope. `messageFa` is what the user sees.
class ApiError implements Exception {
  const ApiError({
    required this.code,
    required this.messageFa,
    required this.status,
  });

  factory ApiError.fromJson(int status, Json j) {
    final e = asJson(j['error']);
    return ApiError(
      code: e['code'] as String,
      messageFa: e['messageFa'] as String,
      status: status,
    );
  }

  /// The server never answered: no connection, or it timed out. Client-side only, like the
  /// player's own `NETWORK`.
  factory ApiError.network() => const ApiError(
    code: 'NETWORK',
    messageFa: 'اتصال به سرور برقرار نشد. اتصال اینترنت خود را بررسی کنید.',
    status: 0,
  );

  /// An answer that is not the contract: a proxy's error page, or a cut-off body.
  factory ApiError.unexpected(int status) => ApiError(
    code: 'INTERNAL',
    messageFa: 'سرور کلاس‌ها پاسخ درستی نداد. کمی بعد دوباره امتحان کنید.',
    status: status,
  );

  final String code;
  final String messageFa;
  final int status;

  @override
  String toString() => 'ApiError($status $code)';
}
