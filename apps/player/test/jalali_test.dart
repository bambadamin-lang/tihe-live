import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_player/core/theme/jalali.dart';

void main() {
  group('toPersianDigits', () {
    test('converts Western digits', () {
      expect(JalaliFormat.toPersianDigits('1405'), '۱۴۰۵');
      expect(JalaliFormat.toPersianDigits('0'), '۰');
      expect(JalaliFormat.toPersianDigits('9876543210'), '۹۸۷۶۵۴۳۲۱۰');
    });

    test('leaves non-digits alone', () {
      expect(JalaliFormat.toPersianDigits('جلسه 4'), 'جلسه ۴');
      expect(JalaliFormat.toPersianDigits('1:28:30'), '۱:۲۸:۳۰');
    });

    test('is a no-op on text with no digits', () {
      expect(JalaliFormat.toPersianDigits('مشتق'), 'مشتق');
      expect(JalaliFormat.toPersianDigits(''), '');
    });

    test('does not touch Persian digits that are already converted', () {
      // Applied at the end of formatting, so double application must be harmless.
      expect(JalaliFormat.toPersianDigits('۱۴۰۵'), '۱۴۰۵');
    });
  });

  group('duration', () {
    test('omits the hour component under an hour', () {
      expect(JalaliFormat.duration(const Duration(minutes: 5, seconds: 7)), '۰۵:۰۷');
    });

    test('includes hours for a long lecture', () {
      expect(JalaliFormat.duration(const Duration(hours: 1, minutes: 28, seconds: 30)), '۱:۲۸:۳۰');
    });

    test('pads minutes and seconds', () {
      expect(JalaliFormat.duration(const Duration(hours: 2, minutes: 3, seconds: 4)), '۲:۰۳:۰۴');
    });

    test('handles zero', () {
      expect(JalaliFormat.duration(Duration.zero), '۰۰:۰۰');
    });

    test('handles a duration over ten hours', () {
      expect(JalaliFormat.duration(const Duration(hours: 12, minutes: 0)), '۱۲:۰۰:۰۰');
    });
  });

  group('longDate', () {
    test('converts a Gregorian date to Jalali with a Persian month name', () {
      // 2026-09-27 falls in Mehr 1405.
      final formatted = JalaliFormat.longDate(DateTime.utc(2026, 9, 27, 12));
      expect(formatted, contains('مهر'));
      expect(formatted, contains('۱۴۰۵'));
    });

    test('uses Persian digits throughout', () {
      final formatted = JalaliFormat.longDate(DateTime.utc(2026, 3, 21, 12));
      // No Western digit should survive into user-facing text.
      expect(RegExp(r'[0-9]').hasMatch(formatted), isFalse);
    });
  });

  group('shortDate', () {
    test('is zero-padded and slash-separated', () {
      final formatted = JalaliFormat.shortDate(DateTime.utc(2026, 9, 27, 12));
      expect(formatted.split('/').length, 3);
      expect(RegExp(r'[0-9]').hasMatch(formatted), isFalse);
    });
  });

  group('relative', () {
    test('describes the present moment', () {
      expect(JalaliFormat.relative(DateTime.now().toUtc()), 'همین حالا');
    });

    test('describes minutes, hours and days', () {
      final now = DateTime.now().toUtc();
      expect(JalaliFormat.relative(now.subtract(const Duration(minutes: 5))), contains('دقیقه'));
      expect(JalaliFormat.relative(now.subtract(const Duration(hours: 3))), contains('ساعت'));
      expect(JalaliFormat.relative(now.subtract(const Duration(days: 2))), contains('روز'));
    });

    test('falls back to an absolute date beyond a week', () {
      // "۴۰ روز پیش" is less useful than the date itself.
      final old = DateTime.now().toUtc().subtract(const Duration(days: 40));
      expect(JalaliFormat.relative(old), isNot(contains('پیش')));
    });
  });

  group('spokenDuration', () {
    test('uses minutes under an hour', () {
      expect(JalaliFormat.spokenDuration(const Duration(minutes: 45)), '۴۵ دقیقه');
    });

    test('combines hours and minutes', () {
      expect(
        JalaliFormat.spokenDuration(const Duration(hours: 2, minutes: 15)),
        '۲ ساعت و ۱۵ دقیقه',
      );
    });

    test('drops zero minutes on a whole hour', () {
      expect(JalaliFormat.spokenDuration(const Duration(hours: 3)), '۳ ساعت');
    });

    test('rounds to the nearest minute', () {
      expect(JalaliFormat.spokenDuration(const Duration(minutes: 9, seconds: 31)), '۱۰ دقیقه');
      expect(JalaliFormat.spokenDuration(const Duration(minutes: 59, seconds: 45)), '۱ ساعت');
    });

    test('never shows zero for something with length', () {
      expect(JalaliFormat.spokenDuration(const Duration(seconds: 5)), '۱ دقیقه');
      expect(JalaliFormat.spokenDuration(Duration.zero), '۰ دقیقه');
    });
  });

  group('speed', () {
    test('whole speeds have no decimal', () {
      expect(JalaliFormat.speed(1), '۱×');
      expect(JalaliFormat.speed(2), '۲×');
    });

    test('fractional speeds use the Persian decimal separator', () {
      expect(JalaliFormat.speed(1.25), '۱٫۲۵×');
      expect(JalaliFormat.speed(0.5), '۰٫۵×');
      expect(JalaliFormat.speed(1.5), '۱٫۵×');
    });
  });

  group('schedule', () {
    // Built in local time and handed over as UTC, as the API sends it, so the expected clock
    // reading holds in whatever time zone the tests run.
    final now = DateTime(2026, 10, 4, 8, 15); // Sunday 12 Mehr 1405

    test('says today, tomorrow and yesterday rather than a date', () {
      expect(
        JalaliFormat.schedule(DateTime(2026, 10, 4, 10, 30).toUtc(), now: now),
        'امروز، ۱۰:۳۰',
      );
      expect(JalaliFormat.schedule(DateTime(2026, 10, 5, 18, 0).toUtc(), now: now), 'فردا، ۱۸:۰۰');
      expect(JalaliFormat.schedule(DateTime(2026, 10, 3, 9, 5).toUtc(), now: now), 'دیروز، ۰۹:۰۵');
    });

    test('names the weekday and Jalali date further out', () {
      expect(
        JalaliFormat.schedule(DateTime(2026, 10, 10, 10, 30).toUtc(), now: now),
        'شنبه ۱۸ مهر، ۱۰:۳۰',
      );
    });

    test('adds the year only when it differs', () {
      expect(
        JalaliFormat.schedule(DateTime(2027, 3, 25, 9, 0).toUtc(), now: now),
        'پنجشنبه ۵ فروردین ۱۴۰۶، ۰۹:۰۰',
      );
    });

    test('a class just after midnight is tomorrow, not today', () {
      final late = DateTime(2026, 10, 4, 23, 50);
      expect(JalaliFormat.schedule(DateTime(2026, 10, 5, 0, 10).toUtc(), now: late), 'فردا، ۰۰:۱۰');
    });
  });
}
