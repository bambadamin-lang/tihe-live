import 'package:shamsi_date/shamsi_date.dart';

/// Jalali (Shamsi) date formatting.
///
/// Everything the server stores is UTC (see docs/07-data-model.md); conversion happens here and
/// nowhere else. A student seeing a Gregorian date in an otherwise Persian interface reads it as a
/// bug, and rightly so.
class JalaliFormat {
  const JalaliFormat._();

  static const _months = [
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];

  /// `۱۵ مهر ۱۴۰۵`
  static String longDate(DateTime utc) {
    final local = utc.toLocal();
    final jalali = Jalali.fromDateTime(local);
    return '${toPersianDigits(jalali.day.toString())} '
        '${_months[jalali.month - 1]} '
        '${toPersianDigits(jalali.year.toString())}';
  }

  /// `۱۴۰۵/۰۷/۱۵`
  static String shortDate(DateTime utc) {
    final jalali = Jalali.fromDateTime(utc.toLocal());
    final month = jalali.month.toString().padLeft(2, '0');
    final day = jalali.day.toString().padLeft(2, '0');
    return toPersianDigits('${jalali.year}/$month/$day');
  }

  /// Relative where it reads better than a date — "۳ روز پیش" rather than a date for recent items.
  static String relative(DateTime utc) {
    final difference = DateTime.now().difference(utc.toLocal());

    if (difference.inMinutes < 1) return 'همین حالا';
    if (difference.inMinutes < 60) return '${toPersianDigits('${difference.inMinutes}')} دقیقه پیش';
    if (difference.inHours < 24) return '${toPersianDigits('${difference.inHours}')} ساعت پیش';
    if (difference.inDays < 7) return '${toPersianDigits('${difference.inDays}')} روز پیش';
    return longDate(utc);
  }

  /// Durations read right-to-left as `۱:۲۸:۳۰`, so the components are built then converted.
  static String duration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final text = hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
    return toPersianDigits(text);
  }

  /// Western digits to Persian. Applied at the very end of formatting, never to data.
  static String toPersianDigits(String input) {
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        buffer.write(persian[rune - 0x30]);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }
}
