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
      expect(
        JalaliFormat.duration(const Duration(hours: 1, minutes: 28, seconds: 30)),
        '۱:۲۸:۳۰',
      );
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
}
