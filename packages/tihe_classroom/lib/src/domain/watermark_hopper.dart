import 'dart:math';

/// The rows of a watermark text, top to bottom: the name with the full phone beneath it
/// (watermarkSchema in the contract). Blank rows are dropped.
List<String> watermarkRows(String text) =>
    text.split('\n').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();

/// Whether a watermark row is the phone number (as against the name).
bool isWatermarkPhone(String row) => RegExp(r'^\+?\d{10,13}$').hasMatch(row);

/// The number as everyone but its owner may see it, `0912•••4503` — the same rule as
/// `maskPhone` in the contracts.
String maskWatermarkPhone(String row) {
  final local = row.replaceFirst(RegExp(r'^\+98'), '0');
  if (local.length < 11) return '•' * local.length;
  return '${local.substring(0, 4)}•••${local.substring(local.length - 4)}';
}

/// Where on the stage the watermark can sit, in reading terms so RTL is handled by the layout:
/// the four corners and the centre.
enum WatermarkSpot {
  topStart,
  topEnd,
  center,
  bottomStart,
  bottomEnd;

  static const corners = [topStart, topEnd, bottomStart, bottomEnd];
}

/// Where the watermark sits, and when it jumps next (docs/11 §9).
///
/// The sequence is pseudo-random from the per-join seed: the mark jumps to a *different* spot
/// at intervals between half and one-and-a-half times `periodSeconds`. Cropping the edges, or
/// the middle, out of a recording therefore never removes it, and the rhythm cannot be
/// predicted from another student's copy.
class WatermarkHopper {
  WatermarkHopper({
    required int seed,
    required int periodSeconds,
    List<WatermarkSpot> spots = WatermarkSpot.values,
  }) : assert(
         spots.length >= 2,
         'a watermark that cannot jump is a fixed target',
       ),
       _spots = List.unmodifiable(spots),
       _random = Random(seed),
       _period = Duration(seconds: max(4, periodSeconds)) {
    _spot = _spots[_random.nextInt(_spots.length)];
    _nextAt = _interval();
  }

  /// The spots for the contract's `movement`: `corners` keeps to the four corners; the
  /// classroom's `corners-and-center`, or anything newer, uses all five.
  static List<WatermarkSpot> spotsFor(String movement) =>
      movement == 'corners' ? WatermarkSpot.corners : WatermarkSpot.values;

  final List<WatermarkSpot> _spots;
  final Random _random;
  final Duration _period;
  late WatermarkSpot _spot;
  late Duration _nextAt;

  Duration _interval() => _period * (0.5 + _random.nextDouble());

  /// The spot at [elapsed] time since the class view opened.
  WatermarkSpot spotAt(Duration elapsed) {
    while (elapsed >= _nextAt) {
      final others = _spots.where((s) => s != _spot).toList();
      _spot = others[_random.nextInt(others.length)];
      _nextAt += _interval();
    }
    return _spot;
  }

  /// How long until the next jump — the widget schedules its next rebuild with this.
  Duration untilNext(Duration elapsed) => _nextAt - elapsed;
}
