import 'dart:async';

import 'package:flutter/material.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../domain/watermark_hopper.dart';

/// The identity watermark over the stage (docs/11 §9): the viewer's name, and under it their
/// whole phone number — no short id and no clock, as the institute asked. It jumps between the
/// four corners and the centre of the **stage** at seeded random intervals, sits above every pod
/// and ignores the pointer. The digits stay ASCII so OCR on a leaked copy reads them reliably.
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
    spots: WatermarkHopper.spotsFor(widget.spec.movement),
  );
  late final DateTime _opened;
  late WatermarkSpot _spot;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _opened = widget.clock();
    _follow();
  }

  /// Takes the current spot and sleeps until the next jump: with no clock on the mark, nothing
  /// changes in between, so there is nothing to rebuild.
  void _follow() {
    final elapsed = widget.clock().difference(_opened);
    _spot = _hopper.spotAt(elapsed);
    // A hair past the jump, so a timer that fires early still lands on the new spot.
    _timer = Timer(
      _hopper.untilNext(elapsed) + const Duration(milliseconds: 20),
      () {
        if (mounted) setState(_follow);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alignment = switch (_spot) {
      WatermarkSpot.topStart => AlignmentDirectional.topStart,
      WatermarkSpot.topEnd => AlignmentDirectional.topEnd,
      WatermarkSpot.center => AlignmentDirectional.center,
      WatermarkSpot.bottomStart => AlignmentDirectional.bottomStart,
      WatermarkSpot.bottomEnd => AlignmentDirectional.bottomEnd,
    };
    final label = widget.spec.text;
    // A Persian name sets the lines right to left; a number alone stays left to right.
    final direction = _rtl.hasMatch(label)
        ? TextDirection.rtl
        : TextDirection.ltr;
    final style = TextStyle(
      fontSize: widget.spec.fontSize.toDouble() + 1,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      height: 1.35,
    );
    // Changes only when it jumps: its own layer, so the stage underneath is not repainted.
    return RepaintBoundary(
      child: IgnorePointer(
        child: Padding(
          // Top corners sit below the pods' title strips, over the content, where a crop of
          // the picture still keeps them.
          padding: const EdgeInsets.fromLTRB(26, 44, 26, 22),
          // A jump, not a slide: the mark is whole in every frame, never smeared across the
          // class on its way.
          child: Align(
            alignment: alignment,
            child: Opacity(
              opacity: widget.spec.opacity.clamp(0.1, 0.9),
              // White letters with a dark outline read on both video and the white board.
              child: Stack(
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
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
                    label,
                    textAlign: TextAlign.center,
                    textDirection: direction,
                    style: style.copyWith(color: Colors.white),
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

/// Arabic-script letters (Persian included).
final _rtl = RegExp('[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');

/// For accessibility tools: the watermark is decorative to them, but its presence is announced.
String watermarkSemantics(WatermarkSpec spec) =>
    'واترمارک شناسایی: ${toPersianDigits(spec.text)}';
