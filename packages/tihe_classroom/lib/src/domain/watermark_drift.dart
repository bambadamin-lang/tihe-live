import 'dart:math';

/// The rows of a watermark text, top to bottom: the name with the full phone beneath it
/// (watermarkSchema in the contract).
List<String> watermarkRows(String text) =>
    text.split('\n').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();

/// A point on the stage: `x` from the left edge (0) to the right (1), `y` from the top (0) to
/// the bottom (1). The mark is placed so that it stays whole inside the stage at every point.
typedef StagePoint = ({double x, double y});

/// Where the watermark is at any moment (docs/11 §9).
///
/// It glides over the whole stage — centre and edges, not only the corners — from one seeded
/// random point to the next, rests briefly, and moves on. Each leg crosses at least half the
/// stage, so a camera zoomed in on any part of the picture has the mark pass through its frame
/// within a few legs, and the path cannot be predicted from another student's copy. A leg
/// lasts between 0.6 and 1.4 times `periodSeconds`.
class WatermarkDrift {
  WatermarkDrift({required int seed, required int periodSeconds})
    : _random = Random(seed),
      _period = Duration(seconds: max(6, periodSeconds)) {
    _from = _point();
    _startLeg(Duration.zero);
  }

  /// Every leg crosses at least this far, so the mark never idles in one region.
  static const minLeg = 0.5;

  final Random _random;
  final Duration _period;
  late StagePoint _from;
  late StagePoint _to;
  late Duration _legStart;
  late Duration _glide;
  late Duration _legEnd;

  StagePoint _point() => (x: _random.nextDouble(), y: _random.nextDouble());

  static double _distance(StagePoint a, StagePoint b) =>
      sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));

  void _startLeg(Duration at) {
    var best = _point();
    // A few draws are almost always enough; the farthest one is kept if none reach [minLeg].
    for (var i = 0; i < 8 && _distance(_from, best) < minLeg; i++) {
      final next = _point();
      if (_distance(_from, next) > _distance(_from, best)) best = next;
    }
    _to = best;
    _legStart = at;
    final length = _period * (0.6 + 0.8 * _random.nextDouble());
    // Most of a leg is the glide; the rest is a short pause where the text is easiest to read.
    _glide = length * (0.65 + 0.2 * _random.nextDouble());
    _legEnd = at + length;
  }

  /// The point at [elapsed] time since the class view opened. Time only moves forward.
  StagePoint positionAt(Duration elapsed) {
    while (elapsed >= _legEnd) {
      _from = _to;
      _startLeg(_legEnd);
    }
    final t = ((elapsed - _legStart).inMicroseconds / _glide.inMicroseconds)
        .clamp(0.0, 1.0);
    // Smoothstep: starts and stops gently instead of snapping into motion.
    final e = t * t * (3 - 2 * t);
    return (
      x: _from.x + (_to.x - _from.x) * e,
      y: _from.y + (_to.y - _from.y) * e,
    );
  }
}
