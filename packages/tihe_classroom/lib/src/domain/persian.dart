import 'package:shamsi_date/shamsi_date.dart';

/// Persian presentation helpers. The UI shows Persian digits and Jalali dates; storage and the
/// wire keep UTC ISO strings and ASCII digits (CLAUDE.md rule 5).
const _persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

String toPersianDigits(Object value) => value.toString().replaceAllMapped(
  RegExp('[0-9]'),
  (m) => _persianDigits[int.parse(m[0]!)],
);

const _months = [
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

/// `۵ مهر ۱۴۰۵` in the device's time zone.
String jalaliDate(DateTime utc) {
  final j = Jalali.fromDateTime(utc.toLocal());
  return toPersianDigits('${j.day} ${_months[j.month - 1]} ${j.year}');
}

/// `۱۴:۳۲` in the device's time zone.
String clockTime(DateTime utc) {
  final t = utc.toLocal();
  return toPersianDigits(
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
  );
}

/// `۰۱:۲۳:۴۵` since the class started — the LIVE plaque.
String elapsedClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return toPersianDigits(
    '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}',
  );
}
