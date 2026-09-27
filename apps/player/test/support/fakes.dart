import 'package:flutter/material.dart';
import 'package:tihe_player/core/api/models.dart';
import 'package:tihe_player/core/api/repositories.dart';
import 'package:tihe_player/core/preferences.dart';
import 'package:tihe_player/core/providers.dart';

/// Realistic Persian fixtures, long enough to expose layout problems a two-letter title hides.

const _policy = CoursePolicy(
  allowDownload: true,
  allowCapture: false,
  offlineWindowDays: 30,
  maxDevices: 2,
);

Video fakeVideo(
  String id,
  String title, {
  String status = 'ready',
  int minutes = 64,
  int progressMinutes = 0,
  bool completed = false,
  String? lockedReason,
  List<Chapter> chapters = const [],
}) =>
    Video(
      id: id,
      courseId: 'crs_1',
      title: title,
      duration: Duration(minutes: minutes, seconds: 17),
      status: status,
      progress: Duration(minutes: progressMinutes),
      completed: completed,
      downloaded: completed,
      lockedReason: lockedReason,
      recordedAt: DateTime.utc(2026, 9, 1),
      chapters: chapters,
    );

final fakeCourse = Course(
  id: 'crs_1',
  title: 'ریاضی عمومی ۱ — حد و پیوستگی و مشتق‌پذیری توابع یک‌متغیره',
  videoCount: 5,
  progress: 0.42,
  policy: _policy,
  teacherName: 'دکتر مریم احمدی',
  description: 'این دوره مفاهیم پایه حسابان را از تعریف دقیق حد تا پیوستگی و مشتق‌پذیری پوشش '
      'می‌دهد و هر جلسه با مثال‌های حل‌شده و تمرین همراه است.',
  sections: [
    CourseSection(
      id: 'sec_1',
      title: 'فصل اول: حد',
      videos: [
        fakeVideo('vid_1', 'جلسه اول — معرفی دوره و مفهوم تابع', completed: true),
        fakeVideo(
          'vid_2',
          'جلسه دوم — تعریف دقیق حد و قضیه فشردگی با مثال‌های متعدد',
          progressMinutes: 18,
          chapters: const [
            Chapter(id: 'ch_1', title: 'مرور جلسه قبل', start: Duration.zero),
            Chapter(id: 'ch_2', title: 'تعریف دقیق حد', start: Duration(minutes: 9)),
            Chapter(id: 'ch_3', title: 'قضیه فشردگی', start: Duration(minutes: 41)),
          ],
        ),
        fakeVideo('vid_3', 'جلسه سوم — حل تمرین', lockedReason: 'پس از قبولی در آزمونک باز می‌شود'),
      ],
    ),
  ],
  looseVideos: [
    fakeVideo('vid_4', 'جلسه چهارم — پیوستگی'),
    fakeVideo('vid_5', 'جلسه پنجم — کلاس رفع اشکال', status: 'processing', minutes: 0),
  ],
);

final fakeCourses = [
  fakeCourse,
  const Course(
    id: 'crs_2',
    title: 'برنامه‌نویسی پایتون مقدماتی',
    videoCount: 16,
    progress: 1,
    policy: CoursePolicy(
      allowDownload: false,
      allowCapture: false,
      offlineWindowDays: 30,
      maxDevices: 2,
    ),
    teacherName: 'مهندس علی رضایی',
  ),
  const Course(id: 'crs_3', title: 'آمار و احتمال', videoCount: 12, progress: 0, policy: _policy),
];

final fakeSession = Session(
  user: const AppUser(
    id: 'usr_1',
    phoneMasked: '0912•••6789',
    role: 'student',
    displayName: 'نیلوفر حسینی',
  ),
  device: Device(
    id: 'dev_1',
    platform: 'windows',
    name: 'Laptop',
    isCurrent: true,
    offlineVideoCount: 0,
    lastSeenAt: DateTime.utc(2026, 9, 1),
  ),
);

final fakeDevices = [
  Device(
    id: 'dev_1',
    platform: 'windows',
    name: 'لپ‌تاپ خانه — Windows 11 Pro',
    isCurrent: true,
    offlineVideoCount: 3,
    lastSeenAt: DateTime.now().toUtc(),
  ),
  Device(
    id: 'dev_2',
    platform: 'android',
    name: 'Samsung Galaxy A54',
    isCurrent: false,
    offlineVideoCount: 7,
    lastSeenAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
  ),
];

class FakeAuth extends AuthController {
  FakeAuth(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;
}

class FixedThemeMode extends ThemeModeController {
  FixedThemeMode(this.mode);

  final ThemeMode mode;

  @override
  ThemeMode build() => mode;
}

class FakeCatalog implements CatalogRepository {
  @override
  Future<List<Course>> courses() async => fakeCourses;

  @override
  Future<Course> course(String id) async => fakeCourse;

  @override
  Future<Video> video(String id) async => fakeCourse.allVideos.firstWhere((v) => v.id == id);

  @override
  Future<List<SearchHit>> search(String query, {String? courseId}) async => [
        SearchHit(kind: 'course', course: fakeCourse),
        SearchHit(kind: 'video', video: fakeCourse.allVideos[1]),
      ];
}

class FakePlayback implements PlaybackRepository {
  final ended = <String>[];

  @override
  Future<PlaybackSession> start({
    required String videoId,
    required String deviceId,
    Map<String, bool>? environment,
  }) async =>
      PlaybackSession(
        sessionId: 'pbs_$videoId',
        videoId: videoId,
        manifestUrl: 'https://example.invalid/master.m3u8',
        wrappedKey: 'sealed',
        keyId: 'key_1',
        watermark: const Watermark(
          text: '0912•••6789 · #8B7C',
          opacity: 0.28,
          fontSize: 13,
          movement: 'drift',
          period: Duration(seconds: 47),
          seed: 918273,
        ),
        blockCapture: true,
        expiresAt: DateTime.utc(2030),
        heartbeatInterval: const Duration(seconds: 30),
        revocationEpoch: 0,
      );

  @override
  Future<void> end(String sessionId) async => ended.add(sessionId);

  @override
  Future<({bool stop, String? reason, int revocationEpoch})> heartbeat(
    String sessionId,
    Duration position,
  ) async =>
      (stop: false, reason: null, revocationEpoch: 0);
}
