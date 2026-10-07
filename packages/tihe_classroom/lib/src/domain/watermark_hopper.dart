import 'dart:math';

/// The rows of a watermark text, top to bottom: the name with the full phone beneath it
/// (watermarkSchema in the contract).
List<String> watermarkRows(String text) =>
    text.split('\n').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();

/// Where the watermark may sit: the four corners of the stage and its exact centre. Corners are
/// in reading terms so RTL is handled by the layout.
enum StageSpot { topStart, topEnd, center, bottomStart, bottomEnd }

/// Where the watermark sits, and when it moves next (docs/11 §9).
///
/// The sequence is pseudo-random from the per-join seed: the mark jumps to a *different* spot
/// at intervals between half and one-and-a-half times `periodSeconds`. The centre spot means a
/// camera zoomed in past the corners still catches it, and the rhythm cannot be predicted from
/// another student's copy.
class WatermarkHopper {
  WatermarkHopper({required int seed, required int periodSeconds})
    : _random = Random(seed),
      _period = Duration(seconds: max(4, periodSeconds)) {
    _spot = StageSpot.values[_random.nextInt(StageSpot.values.length)];
    _nextAt = _interval();
  }

  final Random _random;
  final Duration _period;
  late StageSpot _spot;
  late Duration _nextAt;

  Duration _interval() => _period * (0.5 + _random.nextDouble());

  /// The spot at [elapsed] time since the class view opened. Time only moves forward.
  StageSpot spotAt(Duration elapsed) {
    while (elapsed >= _nextAt) {
      final others = StageSpot.values.where((s) => s != _spot).toList();
      _spot = others[_random.nextInt(others.length)];
      _nextAt += _interval();
    }
    return _spot;
  }

  /// How long until the next jump.
  Duration untilNext(Duration elapsed) => _nextAt - elapsed;
}
