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

  static const _weekdays = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'];

  /// `۱۰:۳۰`, local time, 24-hour as clocks in Iran read.
  static String time(DateTime utc) {
    final local = utc.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return toPersianDigits('$hour:$minute');
  }

  /// When something is scheduled, as a student would say it: `امروز، ۱۰:۳۰`, `فردا، ۱۸:۰۰`,
  /// `شنبه ۱۹ مهر، ۱۰:۳۰`, with the year only when it is not this year. [now] is for tests.
  static String schedule(DateTime utc, {DateTime? now}) {
    final local = utc.toLocal();
    final today = now?.toLocal() ?? DateTime.now();
    // Whole calendar days, counted on dates alone so a clock change cannot make it 0.96 of one.
    final days = DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    final String day;
    if (days == 0) {
      day = 'امروز';
    } else if (days == 1) {
      day = 'فردا';
    } else if (days == -1) {
      day = 'دیروز';
    } else {
      final date = Jalali.fromDateTime(local);
      final year = date.year == Jalali.fromDateTime(today).year
          ? ''
          : ' ${toPersianDigits('${date.year}')}';
      day =
          '${_weekdays[date.weekDay - 1]} ${toPersianDigits('${date.day}')} '
          '${_months[date.month - 1]}$year';
    }
    return '$day، ${time(utc)}';
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

  /// A rounded, spoken length for totals: `۲ ساعت و ۱۵ دقیقه`, `۴۵ دقیقه`.
  ///
  /// For a course's total length, where seconds are noise. Rounds to the nearest minute, and never
  /// shows zero minutes for something that has any length at all.
  static String spokenDuration(Duration d) {
    if (d <= Duration.zero) return '${toPersianDigits('0')} دقیقه';
    final totalMinutes = ((d.inSeconds + 30) ~/ 60).clamp(1, 1 << 31);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '${toPersianDigits('$minutes')} دقیقه';
    if (minutes == 0) return '${toPersianDigits('$hours')} ساعت';
    return '${toPersianDigits('$hours')} ساعت و ${toPersianDigits('$minutes')} دقیقه';
  }

  /// A playback speed as Persian text with the Persian decimal separator: `۱٫۲۵×`.
  static String speed(double value) {
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString().replaceAll(RegExp(r'0+$'), '');
    return '${toPersianDigits(text).replaceAll('.', '٫')}×';
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
