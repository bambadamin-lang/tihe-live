import 'dart:async';

import 'package:flutter/material.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../domain/watermark_hopper.dart';

/// The identity watermark over the stage (docs/11 §9): masked phone, short account id and the
/// time, in a corner that changes at seeded random intervals. It sits above every pod and
/// ignores the pointer. The digits stay ASCII so OCR on a leaked copy reads them reliably.
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

class _WatermarkOverlayState extends State<WatermarkOverlay> {
  late final WatermarkHopper _hopper = WatermarkHopper(
    seed: widget.spec.seed,
    periodSeconds: widget.spec.periodSeconds,
  );
  late final DateTime _opened = widget.clock();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Once a second is enough: the clock shows minutes, and corner jumps are seconds apart.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final corner = _hopper.cornerAt(now.difference(_opened));
    final local = now.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final alignment = switch (corner) {
      StageCorner.topStart => AlignmentDirectional.topStart,
      StageCorner.topEnd => AlignmentDirectional.topEnd,
      StageCorner.bottomStart => AlignmentDirectional.bottomStart,
      StageCorner.bottomEnd => AlignmentDirectional.bottomEnd,
    };
    final label = '${widget.spec.text} · $time';
    final style = TextStyle(
      fontSize: widget.spec.fontSize.toDouble() + 1,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return IgnorePointer(
      child: Padding(
        // Top corners sit below the pods' title strips, over the content, where a crop of
        // the picture still keeps them.
        padding: const EdgeInsets.fromLTRB(26, 44, 26, 22),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          alignment: alignment,
          child: Opacity(
            opacity: widget.spec.opacity.clamp(0.1, 0.9),
            // White letters with a dark outline read on both video and the white board.
            child: Stack(
              children: [
                Text(
                  label,
                  textDirection: TextDirection.ltr,
                  style: style.copyWith(
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 3
                      ..strokeJoin = StrokeJoin.round
                      ..color = Colors.black87,
                  ),
                ),
                Text(
                  label,
                  textDirection: TextDirection.ltr,
                  style: style.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// For accessibility tools: the watermark is decorative to them, but its presence is announced.
String watermarkSemantics(WatermarkSpec spec) =>
    'واترمارک شناسایی: ${toPersianDigits(spec.text)}';
