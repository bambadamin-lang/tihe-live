import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_player/core/api/api_error.dart';
import 'package:tihe_player/core/api/models.dart';

void main() {
  group('Video', () {
    Map<String, dynamic> json({
      String status = 'ready',
      int durationMs = 600000,
      int progressMs = 0,
      bool completed = false,
      String? lockedReason,
    }) => {
      'id': 'vid_01J8ZQK5T9XVWR3M2N4P6H8B7C',
      'courseId': 'crs_01J8ZQK5T9XVWR3M2N4P6H8B7C',
      'title': 'جلسه ۴ — مشتق',
      'durationMs': durationMs,
      'status': status,
      'progressMs': progressMs,
      'completed': completed,
      'downloaded': false,
      'lockedReason': lockedReason,
    };

    test('parses a ready video', () {
      final video = Video.fromJson(json());
      expect(video.isReady, isTrue);
      expect(video.isProcessing, isFalse);
      expect(video.duration, const Duration(minutes: 10));
    });

    test('reports a processing video as not ready', () {
      // A processing video must not be tappable, or the student hits VIDEO_NOT_READY.
      expect(Video.fromJson(json(status: 'processing')).isReady, isFalse);
    });

    test('hasProgress is true only when part-watched', () {
      expect(Video.fromJson(json(progressMs: 0)).hasProgress, isFalse);
      expect(Video.fromJson(json(progressMs: 120000)).hasProgress, isTrue);
      // A finished video offers "play", not "resume".
      expect(Video.fromJson(json(progressMs: 600000, completed: true)).hasProgress, isFalse);
    });

    test('progressFraction does not divide by zero', () {
      // A still-processing video has no duration yet, and a crash here would break the whole list.
      expect(Video.fromJson(json(durationMs: 0, progressMs: 5000)).progressFraction, 0);
    });

    test('progressFraction is a fraction of the duration', () {
      expect(Video.fromJson(json(progressMs: 150000)).progressFraction, closeTo(0.25, 0.001));
    });

    test('isLocked follows lockedReason', () {
      expect(Video.fromJson(json()).isLocked, isFalse);
      expect(Video.fromJson(json(lockedReason: 'آزمون قبلی را کامل کنید')).isLocked, isTrue);
    });

    test('tolerates missing optional fields', () {
      // The client must not crash on a response from a newer or older API.
      final video = Video.fromJson({
        'id': 'vid_01J8ZQK5T9XVWR3M2N4P6H8B7C',
        'courseId': 'crs_01J8ZQK5T9XVWR3M2N4P6H8B7C',
        'title': 'x',
      });
      expect(video.duration, Duration.zero);
      expect(video.status, 'processing');
      expect(video.chapters, isEmpty);
    });
  });

  group('Course', () {
    test('allVideos flattens sections before loose videos', () {
      final course = Course.fromJson({
        'id': 'crs_01J8ZQK5T9XVWR3M2N4P6H8B7C',
        'title': 'ریاضی',
        'videoCount': 3,
        'progress': 0.5,
        'policy': {
          'allowDownload': true,
          'allowCapture': false,
          'offlineWindowDays': 30,
          'maxDevices': 2,
          'maxConcurrentStreams': 1,
        },
        'sections': [
          {
            'id': 'sec_01J8ZQK5T9XVWR3M2N4P6H8B7C',
            'title': 'فصل ۱',
            'videos': [
              {
                'id': 'vid_01J8ZQK5T9XVWR3M2N4P6H8B7A',
                'courseId': 'crs_01J8ZQK5T9XVWR3M2N4P6H8B7C',
                'title': 'الف',
              },
            ],
          },
        ],
        'looseVideos': [
          {
            'id': 'vid_01J8ZQK5T9XVWR3M2N4P6H8B7B',
            'courseId': 'crs_01J8ZQK5T9XVWR3M2N4P6H8B7C',
            'title': 'ب',
          },
        ],
      });

      expect(course.allVideos.map((v) => v.title).toList(), ['الف', 'ب']);
    });

    Video video(
      String id, {
      String status = 'ready',
      int durationMs = 600000,
      int progressMs = 0,
      bool completed = false,
      String? lockedReason,
    }) => Video(
      id: id,
      courseId: 'crs_1',
      title: id,
      duration: Duration(milliseconds: durationMs),
      status: status,
      progress: Duration(milliseconds: progressMs),
      completed: completed,
      downloaded: false,
      lockedReason: lockedReason,
    );

    Course courseOf(List<Video> videos) => Course(
      id: 'crs_1',
      title: 'ریاضی',
      videoCount: videos.length,
      progress: 0,
      policy: const CoursePolicy(
        allowDownload: false,
        allowCapture: false,
        offlineWindowDays: 30,
        maxDevices: 1,
      ),
      looseVideos: videos,
    );

    test('nextVideo prefers a part-watched session over an earlier unwatched one', () {
      final course = courseOf([
        video('a', completed: true),
        video('b'),
        video('c', progressMs: 60000),
      ]);
      expect(course.nextVideo?.id, 'c');
    });

    test('nextVideo falls back to the first session not yet completed', () {
      final course = courseOf([video('a', completed: true), video('b'), video('c')]);
      expect(course.nextVideo?.id, 'b');
    });

    test('nextVideo restarts a finished course from the top', () {
      final course = courseOf([video('a', completed: true), video('b', completed: true)]);
      expect(course.nextVideo?.id, 'a');
    });

    test('nextVideo never offers a locked or processing session', () {
      // Offering one would send the student straight into VIDEO_NOT_READY or a lock screen.
      final course = courseOf([
        video('a', status: 'processing'),
        video('b', lockedReason: 'quiz'),
        video('c'),
      ]);
      expect(course.nextVideo?.id, 'c');
      expect(courseOf([video('a', status: 'processing')]).nextVideo, isNull);
    });

    test('neighboursOf skips sessions that cannot be played', () {
      final course = courseOf([
        video('a'),
        video('b', lockedReason: 'quiz'),
        video('c'),
        video('d', status: 'processing'),
      ]);
      final middle = course.neighboursOf('c');
      expect(middle.previous?.id, 'a');
      expect(middle.next, isNull);

      final first = course.neighboursOf('a');
      expect(first.previous, isNull);
      expect(first.next?.id, 'c');
    });

    test('neighboursOf returns nothing for a video not in the course', () {
      final result = courseOf([video('a')]).neighboursOf('zzz');
      expect(result.previous, isNull);
      expect(result.next, isNull);
    });

    test('totals count every session', () {
      final course = courseOf([
        video('a', durationMs: 60000, completed: true),
        video('b', durationMs: 120000),
      ]);
      expect(course.totalDuration, const Duration(minutes: 3));
      expect(course.completedCount, 1);
    });
  });

  group('PlaybackSession', () {
    test('parses a session and its watermark', () {
      final session = PlaybackSession.fromJson({
        'sessionId': 'ps_01J8ZQK5T9XVWR3M2N4P6H8B7C',
        'videoId': 'vid_01J8ZQK5T9XVWR3M2N4P6H8B7C',
        'manifestUrl': 'https://example.test/master.m3u8',
        'segmentBaseUrl': 'https://example.test/720p/',
        'wrappedKey': 'aGVsbG8=',
        'encryption': {
          'scheme': 'AES-128-CTR',
          'ivMode': 'per-segment-sequence',
          'keyId': 'ck_01J8ZQK5T9XVWR3M2N4P6H8B7C',
        },
        'watermark': {
          'text': '0912•••6789 · #8B7C',
          'opacity': 0.28,
          'fontSize': 13,
          'movement': 'drift',
          'periodSeconds': 47,
          'seed': 918273,
        },
        'blockCapture': true,
        'expiresAt': '2026-09-27T14:00:00.000Z',
        'heartbeatIntervalSeconds': 30,
        'revocationEpoch': 3,
      });

      expect(session.blockCapture, isTrue);
      expect(session.heartbeatInterval, const Duration(seconds: 30));
      expect(session.watermark.movement, 'drift');
      // The mark carries a masked number, never a full one.
      expect(session.watermark.text, isNot(contains('3456')));
    });

    test('defaults blockCapture to true when the server omits it', () {
      // Failing closed: an older server that does not send the flag must not disable capture
      // blocking.
      final session = PlaybackSession.fromJson({
        'sessionId': 'ps_01J8ZQK5T9XVWR3M2N4P6H8B7C',
        'videoId': 'vid_01J8ZQK5T9XVWR3M2N4P6H8B7C',
        'manifestUrl': 'https://example.test/master.m3u8',
        'wrappedKey': 'aGVsbG8=',
        'encryption': {'keyId': 'ck_01J8ZQK5T9XVWR3M2N4P6H8B7C'},
        'watermark': {
          'text': 'x',
          'opacity': 0.3,
          'fontSize': 12,
          'movement': 'drift',
          'periodSeconds': 47,
          'seed': 1,
        },
        'expiresAt': '2026-09-27T14:00:00.000Z',
      });

      expect(session.blockCapture, isTrue);
    });
  });

  group('ApiError', () {
    ApiError of(String code) => ApiError(code: code, message: '', messageFa: '');

    test('classifies errors that require re-authentication', () {
      expect(of('TOKEN_EXPIRED').requiresReauth, isTrue);
      expect(of('DEVICE_REVOKED').requiresReauth, isTrue);
      expect(of('NOT_ENROLLED').requiresReauth, isFalse);
    });

    test('routes the device limit to the device manager', () {
      // The student needs somewhere to act, not just a refusal.
      expect(of('DEVICE_LIMIT_REACHED').needsDeviceManager, isTrue);
    });

    test('classifies licence problems as needing the institute', () {
      for (final code in [
        'LICENSE_MISSING',
        'LICENSE_EXPIRED',
        'LICENSE_REVOKED',
        'NOT_ENROLLED',
      ]) {
        expect(of(code).needsSupport, isTrue, reason: code);
      }
    });

    test('marks transient failures retryable', () {
      expect(of('RATE_LIMITED').isRetryable, isTrue);
      expect(of('VIDEO_NOT_READY').isRetryable, isTrue);
      expect(of('INTERNAL').isRetryable, isTrue);
      expect(of('FORBIDDEN').isRetryable, isFalse);
      expect(of('INVALID_CREDENTIALS').isRetryable, isFalse);
    });

    test('parses the server envelope', () {
      final error = ApiError.fromJson({
        'error': {
          'code': 'LICENSE_EXPIRED',
          'message': 'License expired',
          'messageFa': 'اعتبار دسترسی شما به پایان رسیده است',
          'requestId': 'req_01J8ZQK5T9XVWR3M2N4P6H8B7C',
        },
      });

      expect(error.code, 'LICENSE_EXPIRED');
      expect(error.messageFa, isNotEmpty);
      expect(error.requestId, isNotNull);
    });

    test('falls back safely on a malformed envelope', () {
      // A 500 from a proxy will not have our shape; the student must still see Persian text.
      final error = ApiError.fromJson({'unexpected': true});
      expect(error.code, 'INTERNAL');
      expect(error.messageFa, isNotEmpty);
    });
  });
}
