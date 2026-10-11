import 'dart:async';

import 'package:flutter/material.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../domain/watermark_hopper.dart';

/// The identity watermark over the stage (docs/11 §9): the viewer's name, then masked phone,
/// short account id and the time, in a corner that changes at seeded random intervals. It sits
/// above every pod and ignores the pointer. The digits stay ASCII so OCR on a leaked copy reads
/// them reliably.
class WatermarkOverlay extends StatefulWidget {
  const WatermarkOverlay({
    super.key,
    required this.spec,
    this.displayName,
    this.clock = DateTime.now,
  });

  final WatermarkSpec spec;

  /// The viewer's own name, on a line above the id line, so whoever finds a leaked copy sees
  /// at a glance whose it was. It stays off the id line: a right-to-left name mixed into it
  /// would reorder the digits that OCR reads.
  final String? displayName;
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
    final name = widget.displayName?.trim() ?? '';
    final style = TextStyle(
      fontSize: widget.spec.fontSize.toDouble() + 1,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    // Updates every second: its own layer, so the stage underneath is not repainted with it.
    return RepaintBoundary(
      child: IgnorePointer(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // Both lines hug the corner they are in.
                crossAxisAlignment:
                    corner == StageCorner.topStart ||
                        corner == StageCorner.bottomStart
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  // No fixed direction: in the class's right-to-left, bidi lays out a Persian
                  // or a Latin name correctly.
                  if (name.isNotEmpty) _Outlined(name, style: style),
                  _Outlined(
                    label,
                    style: style,
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White letters with a dark outline, which read on both video and the white board.
class _Outlined extends StatelessWidget {
  const _Outlined(this.text, {required this.style, this.textDirection});

  final String text;
  final TextStyle style;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Text(
        text,
        textDirection: textDirection,
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
        textDirection: textDirection,
        style: style.copyWith(color: Colors.white),
      ),
    ],
  );
}

/// For accessibility tools: the watermark is decorative to them, but its presence is announced.
String watermarkSemantics(WatermarkSpec spec) =>
    'واترمارک شناسایی: ${toPersianDigits(spec.text)}';
