import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/api/models.dart';

/// The on-screen identity watermark.
///
/// **Purpose is attribution, not deterrence.** Nothing here stops a camera pointed at the screen —
/// see docs/08-threat-model.md, T3, the attacker we cannot block. What it does is make every frame
/// that escapes carry the account it escaped from, so a leak can be traced and the licence revoked.
///
/// Design decisions that matter:
///
///  * **Drift, not static.** A mark fixed in one corner is croppable in a single pass over a whole
///    recording. A slow pseudo-random path means a crop that removes it also removes content.
///  * **The path is seeded per session**, so two recordings of the same video by the same student
///    produce different paths — the mark cannot be averaged away by comparing them.
///  * **The text comes from the server** already masked. The client renders it but never composes
///    it, so a patched client cannot substitute someone else's identity.
///
/// M3 moves this into the native view layer above the video surface, so tampering with the Dart
/// widget tree cannot remove it, and the Rust side refuses to start playback if the overlay is not
/// attached. This widget is the same geometry, in Dart, so the visual design can be settled first.
class WatermarkOverlay extends StatefulWidget {
  const WatermarkOverlay({required this.watermark, super.key});

  final Watermark watermark;

  @override
  State<WatermarkOverlay> createState() => _WatermarkOverlayState();
}

class _WatermarkOverlayState extends State<WatermarkOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.watermark.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Never intercepts input: the mark must not swallow a tap meant for the player controls.
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _WatermarkPainter(
            text: widget.watermark.text,
            opacity: widget.watermark.opacity,
            fontSize: widget.watermark.fontSize,
            progress: _controller.value,
            seed: widget.watermark.seed,
            static: widget.watermark.movement == 'static',
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  _WatermarkPainter({
    required this.text,
    required this.opacity,
    required this.fontSize,
    required this.progress,
    required this.seed,
    required this.static,
  });

  final String text;
  final double opacity;
  final double fontSize;

  /// 0–1 through one movement cycle.
  final double progress;
  final int seed;
  final bool static;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: opacity),
          // A dark shadow under light text keeps the mark legible on both a bright lecture slide and
          // a dark video frame. Without it the mark disappears on white backgrounds, which is most
          // of a slide deck.
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: opacity * 0.9),
              blurRadius: 3,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final position = _position(size, painter.size);
    painter.paint(canvas, position);
  }

  /// A Lissajous-style path from the session seed.
  ///
  /// Two incommensurate frequencies give a path that covers the frame without repeating quickly, so
  /// no fixed rectangle contains the mark for long. Inset by the text size so it never clips.
  Offset _position(Size canvasSize, Size textSize) {
    final maxX = (canvasSize.width - textSize.width - 32).clamp(0.0, double.infinity);
    final maxY = (canvasSize.height - textSize.height - 32).clamp(0.0, double.infinity);

    if (static) {
      return Offset(16 + maxX * 0.5, 16 + maxY * 0.92);
    }

    // Seed-derived phase offsets, so two sessions never trace the same path.
    final random = Random(seed);
    final phaseX = random.nextDouble() * 2 * pi;
    final phaseY = random.nextDouble() * 2 * pi;

    final t = progress * 2 * pi;
    // 2:3 frequency ratio: the path closes slowly and sweeps most of the frame.
    final x = (sin(t * 2 + phaseX) + 1) / 2;
    final y = (sin(t * 3 + phaseY) + 1) / 2;

    return Offset(16 + maxX * x, 16 + maxY * y);
  }

  @override
  bool shouldRepaint(_WatermarkPainter old) =>
      old.progress != progress ||
      old.text != text ||
      old.opacity != opacity ||
      old.seed != seed ||
      old.static != static;
}
