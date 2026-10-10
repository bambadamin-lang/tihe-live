import 'dart:async';

import 'package:flutter/material.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../domain/watermark_hopper.dart';
import '../theme/motion.dart';

/// The identity watermark over the stage (docs/11 §9): the viewer's name with their full phone
/// number beneath it, nothing else. It sits in one of five spots — a corner of the stage or its
/// exact centre — and jumps to another at seeded random intervals, never gliding across the
/// stage in between. It sits above every pod and ignores the pointer. The digits stay ASCII so
/// OCR on a leaked copy reads them reliably.
class WatermarkOverlay extends StatefulWidget {
  const WatermarkOverlay({
    super.key,
    required this.spec,
    this.clock = DateTime.now,
  });

  final WatermarkSpec spec;
  final DateTime Function() clock;

  @override
  State<WatermarkOverlay> createState() => _WatermarkOverlayState();
}

/// How far above its new spot the mark comes down from when it lands.
const _drop = 16.0;

class _WatermarkOverlayState extends State<WatermarkOverlay>
    with SingleTickerProviderStateMixin {
  late final WatermarkHopper _hopper = WatermarkHopper(
    seed: widget.spec.seed,
    periodSeconds: widget.spec.periodSeconds,
  );
  late final DateTime _opened;
  late StageSpot _spot;
  // Settled at first: the mark is simply there when the class opens.
  late final AnimationController _landing = AnimationController(
    vsync: this,
    duration: Motion.slow,
    value: 1,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _opened = widget.clock();
    _spot = _hopper.spotAt(Duration.zero);
    // Once a second is enough: jumps are many seconds apart.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final spot = _hopper.spotAt(widget.clock().difference(_opened));
    if (spot == _spot) return;
    setState(() => _spot = spot);
    // Gone from the old spot at once, so it is never seen crossing the stage. The bounce in the
    // new one is what makes the move read as a jump rather than a flicker.
    if (!Motion.reduced(context)) _landing.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _landing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alignment = switch (_spot) {
      StageSpot.topStart => AlignmentDirectional.topStart,
      StageSpot.topEnd => AlignmentDirectional.topEnd,
      StageSpot.center => AlignmentDirectional.center,
      StageSpot.bottomStart => AlignmentDirectional.bottomStart,
      StageSpot.bottomEnd => AlignmentDirectional.bottomEnd,
    };
    final rows = watermarkRows(widget.spec.text);
    final size = widget.spec.fontSize.toDouble();
    // Its own layer, so the stage underneath is not repainted when it moves.
    return RepaintBoundary(
      child: IgnorePointer(
        child: Padding(
          // Top corners sit below the pods' title strips, over the content, where a crop of
          // the picture still keeps them.
          padding: const EdgeInsets.fromLTRB(26, 64, 26, 22),
          child: Align(
            alignment: alignment,
            child: AnimatedBuilder(
              animation: _landing,
              // Down onto the spot with a bounce; once landed, nothing moves until the next jump.
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  0,
                  -_drop * (1 - Curves.bounceOut.transform(_landing.value)),
                ),
                child: child,
              ),
              child: Opacity(
                opacity: widget.spec.opacity.clamp(0.1, 0.9),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final row in rows)
                      _OutlinedText(row, style: _rowStyle(row, size)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The phone is the larger row and spaced out, so no digit merges with its neighbour on a
  /// blurry camera copy.
  TextStyle _rowStyle(String row, double size) {
    if (_isPhone(row)) {
      return TextStyle(
        fontSize: size + 4,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
      );
    }
    return TextStyle(fontSize: size + 2, fontWeight: FontWeight.w700);
  }
}

bool _isPhone(String row) => RegExp(r'^\+?\d{10,13}$').hasMatch(row);

final _rtl = RegExp('[؀-ۿ]');

/// White letters with a dark outline read on both video and the white board.
class _OutlinedText extends StatelessWidget {
  const _OutlinedText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // A Persian name reads right to left; the number left to right.
    final direction = _rtl.hasMatch(text)
        ? TextDirection.rtl
        : TextDirection.ltr;
    return Stack(
      children: [
        Text(
          text,
          textDirection: direction,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.black87,
          ),
        ),
        Text(
          text,
          textDirection: direction,
          style: style.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}

/// For accessibility tools: the watermark is decorative to them, but its presence is announced.
String watermarkSemantics(WatermarkSpec spec) =>
    'واترمارک شناسایی: ${toPersianDigits(watermarkRows(spec.text).join(' '))}';
