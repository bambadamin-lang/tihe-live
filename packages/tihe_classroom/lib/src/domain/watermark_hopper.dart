import 'dart:math';

/// A corner of the stage, in reading terms so RTL is handled by the layout.
enum StageCorner { topStart, topEnd, bottomStart, bottomEnd }

/// Where the watermark sits, and when it moves next (docs/11 §9).
///
/// The sequence is pseudo-random from the per-join seed: the mark jumps to a *different*
/// corner at intervals between half and one-and-a-half times `periodSeconds`. Cropping one
/// corner out of a recording therefore never removes it, and the rhythm cannot be predicted
/// from another student's copy.
class WatermarkHopper {
  WatermarkHopper({required int seed, required int periodSeconds})
    : _random = Random(seed),
      _period = Duration(seconds: max(4, periodSeconds)) {
    _corner = StageCorner.values[_random.nextInt(4)];
    _nextAt = _interval();
  }

  final Random _random;
  final Duration _period;
  late StageCorner _corner;
  late Duration _nextAt;

  Duration _interval() => _period * (0.5 + _random.nextDouble());

  /// The corner at [elapsed] time since the class view opened.
  StageCorner cornerAt(Duration elapsed) {
    while (elapsed >= _nextAt) {
      final others = StageCorner.values.where((c) => c != _corner).toList();
      _corner = others[_random.nextInt(others.length)];
      _nextAt += _interval();
    }
    return _corner;
  }

  /// How long until the next jump — the widget schedules its next rebuild with this.
  Duration untilNext(Duration elapsed) => _nextAt - elapsed;
}
