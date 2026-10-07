import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../domain/watermark_drift.dart';

/// The identity watermark over the stage (docs/11 §9), in two layers:
///
/// - **The mark**: the viewer's name, their full phone number beneath it, then the short id and
///   the time. It glides over the whole stage on a seeded path, so a camera zoomed in on any
///   part of the picture still catches it.
/// - **The ghost**: the number and short id repeated faintly across the stage on a slant, so
///   even a frame the mark is not in carries it.
///
/// Both sit above every pod and ignore the pointer. The digits stay ASCII so OCR on a leaked
/// copy reads them reliably.
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
  late final WatermarkDrift _drift = WatermarkDrift(
    seed: widget.spec.seed,
    periodSeconds: widget.spec.periodSeconds,
  );
  late final DateTime _opened = widget.clock();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // A new point once a second; the one-second linear animation below joins them into a
    // smooth glide without rebuilding every frame.
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
    final at = _drift.positionAt(now.difference(_opened));
    final local = now.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final rows = watermarkRows(widget.spec.text);
    final size = widget.spec.fontSize.toDouble();
    final opacity = widget.spec.opacity.clamp(0.1, 0.9);
    // Updates every second: its own layer, so the stage underneath is not repainted with it.
    return RepaintBoundary(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              // Never changes while the class is open: cached in a layer of its own. Clipped,
              // or the slanted rows would spill over the top bar and the dock.
              child: RepaintBoundary(
                child: ClipRect(
                  child: CustomPaint(
                    painter: _GhostPainter(
                      text: _ghostText(rows),
                      // A painter does not inherit the app's font; hand it over.
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                      fontSize: size,
                      opacity: opacity * 0.22,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                // The top edge sits below the pods' title strips, over the content, where a
                // crop of the picture still keeps it.
                padding: const EdgeInsets.fromLTRB(20, 44, 20, 18),
                child: AnimatedAlign(
                  duration: const Duration(seconds: 1),
                  alignment: Alignment(at.x * 2 - 1, at.y * 2 - 1),
                  child: Opacity(
                    opacity: opacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (i, row) in rows.indexed)
                          _OutlinedText(
                            i == rows.length - 1 ? '$row  $time' : row,
                            style: _rowStyle(row, i == rows.length - 1, size),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The phone is the largest row and spaced out, so no digit merges with its neighbour on a
  /// blurry camera copy; the name is close to it; the id and time are the smallest.
  TextStyle _rowStyle(String row, bool last, double size) {
    if (last) {
      return TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      );
    }
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

/// The ghost repeats only the ASCII rows: a bare number survives faint, slanted and re-encoded
/// far better than Persian letters do. Spaces, not "·", which Modam does not have.
String _ghostText(List<String> rows) {
  final ascii = rows.where((r) => !_rtl.hasMatch(r)).toList();
  return (ascii.isEmpty ? rows : ascii).join('    ');
}

/// White letters with a dark outline read on both video and the white board.
class _OutlinedText extends StatelessWidget {
  const _OutlinedText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // A Persian name reads right to left; numbers and ids left to right.
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

/// [text] tiled across the stage on a slant, staggered row by row so no band of the picture is
/// free of it.
class _GhostPainter extends CustomPainter {
  _GhostPainter({
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    required this.opacity,
  });

  final String text;
  final String? fontFamily;
  final double fontSize;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty || size.isEmpty) return;
    TextPainter painter(Paint foreground) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          foreground: foreground,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final outline = painter(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: opacity),
    );
    final fill = painter(
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    // Sparse enough to read the board through, dense enough that any crop a camera can still
    // read holds a whole copy.
    final stepX = fill.width + fontSize * 16;
    final stepY = fontSize * 12;
    // The rotated grid has to cover the stage's corners too: reach past half its diagonal.
    final reach = size.longestSide * 0.75 + stepX;

    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(-math.pi / 9);
    var row = 0;
    for (var y = -reach; y < reach; y += stepY, row++) {
      final shift = row.isEven ? 0.0 : stepX / 2;
      for (var x = -reach - shift; x < reach; x += stepX) {
        outline.paint(canvas, Offset(x, y));
        fill.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
    outline.dispose();
    fill.dispose();
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.text != text ||
      old.fontFamily != fontFamily ||
      old.fontSize != fontSize ||
      old.opacity != opacity;
}

/// For accessibility tools: the watermark is decorative to them, but its presence is announced.
String watermarkSemantics(WatermarkSpec spec) =>
    'واترمارک شناسایی: ${toPersianDigits(watermarkRows(spec.text).join(' · '))}';
