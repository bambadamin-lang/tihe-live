/// Client models mirroring `packages/contracts`.
///
/// Hand-written for now. M1 generates these from the OpenAPI document the API serves at `/docs-json`,
/// so a breaking change breaks the build rather than production — but hand-writing the first slice
/// keeps the shapes reviewable while they are still settling.
library;

class Session {
  const Session({required this.user, required this.device});

  final AppUser user;
  final Device device;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        device: Device.fromJson(json['device'] as Map<String, dynamic>),
      );
}

class AppUser {
  const AppUser({
    required this.id,
    required this.phoneMasked,
    required this.role,
    this.displayName,
  });

  final String id;

  /// Already masked by the server. The client never receives a full number — including its own.
  final String phoneMasked;
  final String role;
  final String? displayName;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        phoneMasked: json['phoneMasked'] as String,
        role: json['role'] as String,
        displayName: json['displayName'] as String?,
      );
}

class Device {
  const Device({
    required this.id,
    required this.platform,
    required this.name,
    required this.isCurrent,
    required this.offlineVideoCount,
    this.lastSeenAt,
  });

  final String id;
  final String platform;
  final String name;
  final bool isCurrent;
  final int offlineVideoCount;
  final DateTime? lastSeenAt;

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        platform: json['platform'] as String,
        name: json['name'] as String,
        isCurrent: json['isCurrent'] as bool? ?? false,
        offlineVideoCount: json['offlineVideoCount'] as int? ?? 0,
        lastSeenAt: _parseDate(json['lastSeenAt']),
      );
}

/// Per-course protection policy, decided server-side.
///
/// The client reads these to shape the UI — hiding a download button the server would refuse — but
/// never to decide whether something is allowed. Enforcement is the server's.
class CoursePolicy {
  const CoursePolicy({
    required this.allowDownload,
    required this.allowCapture,
    required this.offlineWindowDays,
    required this.maxDevices,
  });

  final bool allowDownload;
  final bool allowCapture;
  final int offlineWindowDays;
  final int maxDevices;

  factory CoursePolicy.fromJson(Map<String, dynamic> json) => CoursePolicy(
        allowDownload: json['allowDownload'] as bool? ?? false,
        allowCapture: json['allowCapture'] as bool? ?? false,
        offlineWindowDays: json['offlineWindowDays'] as int? ?? 30,
        maxDevices: json['maxDevices'] as int? ?? 1,
      );
}

class Course {
  const Course({
    required this.id,
    required this.title,
    required this.videoCount,
    required this.progress,
    required this.policy,
    this.teacherName,
    this.description,
    this.sections = const [],
    this.looseVideos = const [],
  });

  final String id;
  final String title;
  final int videoCount;

  /// 0–1, for the progress ring.
  final double progress;
  final CoursePolicy policy;
  final String? teacherName;
  final String? description;
  final List<CourseSection> sections;
  final List<Video> looseVideos;

  /// Every video in display order, sections first.
  List<Video> get allVideos => [
        for (final section in sections) ...section.videos,
        ...looseVideos,
      ];

  /// Videos the student can open right now, in display order.
  List<Video> get playableVideos => [
        for (final video in allVideos)
          if (video.isReady && !video.isLocked) video,
      ];

  /// Where "continue" goes: the first part-watched session, else the first one not yet completed,
  /// else the first playable one (a finished course restarts from the top). Null when nothing is
  /// playable.
  Video? get nextVideo {
    final playable = playableVideos;
    if (playable.isEmpty) return null;
    for (final video in playable) {
      if (video.hasProgress) return video;
    }
    for (final video in playable) {
      if (!video.completed) return video;
    }
    return playable.first;
  }

  int get completedCount => allVideos.where((v) => v.completed).length;

  Duration get totalDuration => allVideos.fold(Duration.zero, (sum, v) => sum + v.duration);

  /// The playable neighbours of [videoId], for previous/next in the player.
  ({Video? previous, Video? next}) neighboursOf(String videoId) {
    final playable = playableVideos;
    final index = playable.indexWhere((v) => v.id == videoId);
    if (index < 0) return (previous: null, next: null);
    return (
      previous: index > 0 ? playable[index - 1] : null,
      next: index < playable.length - 1 ? playable[index + 1] : null,
    );
  }

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String,
        title: json['title'] as String,
        videoCount: json['videoCount'] as int? ?? 0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        policy: CoursePolicy.fromJson(json['policy'] as Map<String, dynamic>),
        teacherName: json['teacherName'] as String?,
        description: json['description'] as String?,
        sections: (json['sections'] as List<dynamic>? ?? [])
            .map((s) => CourseSection.fromJson(s as Map<String, dynamic>))
            .toList(),
        looseVideos: (json['looseVideos'] as List<dynamic>? ?? [])
            .map((v) => Video.fromJson(v as Map<String, dynamic>))
            .toList(),
      );
}

class CourseSection {
  const CourseSection({required this.id, required this.title, required this.videos});

  final String id;
  final String title;
  final List<Video> videos;

  factory CourseSection.fromJson(Map<String, dynamic> json) => CourseSection(
        id: json['id'] as String,
        title: json['title'] as String,
        videos: (json['videos'] as List<dynamic>? ?? [])
            .map((v) => Video.fromJson(v as Map<String, dynamic>))
            .toList(),
      );
}

class Video {
  const Video({
    required this.id,
    required this.courseId,
    required this.title,
    required this.duration,
    required this.status,
    required this.progress,
    required this.completed,
    required this.downloaded,
    this.lockedReason,
    this.recordedAt,
    this.chapters = const [],
  });

  final String id;
  final String courseId;
  final String title;
  final Duration duration;
  final String status;
  final Duration progress;
  final bool completed;
  final bool downloaded;

  /// Set when a quiz or prerequisite gates this video (M5).
  final String? lockedReason;
  final DateTime? recordedAt;
  final List<Chapter> chapters;

  bool get isReady => status == 'ready';
  bool get isProcessing => status == 'processing';
  bool get isLocked => lockedReason != null;

  /// Whether to show "resume" rather than "play" — and where to seek to.
  bool get hasProgress => progress > Duration.zero && !completed;

  double get progressFraction =>
      duration.inMilliseconds == 0 ? 0 : progress.inMilliseconds / duration.inMilliseconds;

  factory Video.fromJson(Map<String, dynamic> json) => Video(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        title: json['title'] as String,
        duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
        status: json['status'] as String? ?? 'processing',
        progress: Duration(milliseconds: json['progressMs'] as int? ?? 0),
        completed: json['completed'] as bool? ?? false,
        downloaded: json['downloaded'] as bool? ?? false,
        lockedReason: json['lockedReason'] as String?,
        recordedAt: _parseDate(json['recordedAt']),
        chapters: (json['chapters'] as List<dynamic>? ?? [])
            .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class Chapter {
  const Chapter({required this.id, required this.title, required this.start});

  final String id;
  final String title;
  final Duration start;

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        id: json['id'] as String,
        title: json['title'] as String,
        start: Duration(milliseconds: json['startMs'] as int? ?? 0),
      );
}

class SearchHit {
  const SearchHit({required this.kind, this.course, this.video});

  final String kind;
  final Course? course;
  final Video? video;

  String get title => course?.title ?? video?.title ?? '';

  factory SearchHit.fromJson(Map<String, dynamic> json) => SearchHit(
        kind: json['kind'] as String,
        course:
            json['course'] == null ? null : Course.fromJson(json['course'] as Map<String, dynamic>),
        video: json['video'] == null ? null : Video.fromJson(json['video'] as Map<String, dynamic>),
      );
}

/// What the server returns to start protected playback.
///
/// [wrappedKey] is the content key sealed to this device's public key. **It is passed straight to
/// secure-core over FFI and never inspected in Dart** — only the Rust side can open it, using a
/// private key sealed in the platform keystore.
class PlaybackSession {
  const PlaybackSession({
    required this.sessionId,
    required this.videoId,
    required this.manifestUrl,
    required this.wrappedKey,
    required this.keyId,
    required this.watermark,
    required this.blockCapture,
    required this.expiresAt,
    required this.heartbeatInterval,
    required this.revocationEpoch,
  });

  final String sessionId;
  final String videoId;
  final String manifestUrl;
  final String wrappedKey;
  final String keyId;
  final Watermark watermark;

  /// Server decision from course policy, not a client preference.
  final bool blockCapture;
  final DateTime expiresAt;
  final Duration heartbeatInterval;
  final int revocationEpoch;

  factory PlaybackSession.fromJson(Map<String, dynamic> json) => PlaybackSession(
        sessionId: json['sessionId'] as String,
        videoId: json['videoId'] as String,
        manifestUrl: json['manifestUrl'] as String,
        wrappedKey: json['wrappedKey'] as String,
        keyId: (json['encryption'] as Map<String, dynamic>)['keyId'] as String,
        watermark: Watermark.fromJson(json['watermark'] as Map<String, dynamic>),
        blockCapture: json['blockCapture'] as bool? ?? true,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        heartbeatInterval: Duration(seconds: json['heartbeatIntervalSeconds'] as int? ?? 30),
        revocationEpoch: json['revocationEpoch'] as int? ?? 0,
      );
}

/// On-screen identity watermark parameters.
///
/// The text is composed server-side and already masked. The client renders it but does not build it,
/// so a patched client cannot substitute another student's identity.
class Watermark {
  const Watermark({
    required this.text,
    required this.opacity,
    required this.fontSize,
    required this.movement,
    required this.period,
    required this.seed,
  });

  final String text;
  final double opacity;
  final double fontSize;
  final String movement;
  final Duration period;
  final int seed;

  factory Watermark.fromJson(Map<String, dynamic> json) => Watermark(
        text: json['text'] as String,
        opacity: (json['opacity'] as num).toDouble(),
        fontSize: (json['fontSize'] as num).toDouble(),
        movement: json['movement'] as String,
        period: Duration(seconds: json['periodSeconds'] as int? ?? 47),
        seed: json['seed'] as int? ?? 0,
      );
}

DateTime? _parseDate(Object? value) => value is String ? DateTime.tryParse(value) : null;
