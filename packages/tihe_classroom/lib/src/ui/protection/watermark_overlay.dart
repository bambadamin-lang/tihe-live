import 'dart:async';

import 'package:flutter/material.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../domain/watermark_hopper.dart';

/// The identity watermark over the stage (docs/11 §9): the owner's full phone number, short
/// account id and the time, in a corner that changes at seeded random intervals. It sits above
/// every pod and ignores the pointer. The digits stay ASCII so OCR on a leaked copy reads them
/// reliably, and heavy so they survive a phone camera pointed at the screen.
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
    // Updates every second: its own layer, so the stage underneath is not repainted with it.
    return RepaintBoundary(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The server's size is for a desktop stage; a phone's stage gets a smaller mark, a
            // large monitor a larger one, so it reads the same share of the picture.
            final scale = (constraints.biggest.shortestSide / 720).clamp(
              0.75,
              1.3,
            );
            final fontSize = widget.spec.fontSize * scale;
            final style = TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            );
            return Padding(
              // Top corners sit below the pods' title strips, over the content, where a crop
              // of the picture still keeps them.
              padding: const EdgeInsets.fromLTRB(26, 44, 26, 22),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                alignment: alignment,
                // One line always: on a narrow stage it shrinks rather than wraps.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Opacity(
                    opacity: widget.spec.opacity.clamp(0.1, 0.9),
                    // White letters with a dark outline read on both video and the board.
                    child: Stack(
                      children: [
                        Text(
                          label,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          style: style.copyWith(
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = fontSize * 0.22
                              ..strokeJoin = StrokeJoin.round
                              ..color = Colors.black87,
                          ),
                        ),
                        Text(
                          label,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          style: style.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// For accessibility tools: the watermark is decorative to them, but its presence is announced.
String watermarkSemantics(WatermarkSpec spec) =>
    'واترمارک شناسایی: ${toPersianDigits(spec.text)}';
