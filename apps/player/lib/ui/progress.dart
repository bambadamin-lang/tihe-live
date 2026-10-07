import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/tokens.dart';

/// A small, quiet spinner. Sized to sit inside a button or next to a label — the app never shows a
/// large spinner in the middle of a page; loading pages use skeletons instead.
class AppSpinner extends StatelessWidget {
  const AppSpinner({this.size = 16, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: size <= 16 ? 1.75 : 2,
      strokeCap: StrokeCap.round,
      color: color ?? context.colors.textSecondary,
    ),
  );
}

/// A thin, rounded progress track.
///
/// Animates to its value so a refresh reads as change rather than a jump.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    required this.value,
    this.height = 4,
    this.color,
    this.trackColor,
    super.key,
  });

  /// 0–1.
  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      value: '${(value.clamp(0, 1) * 100).round()}%',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: AppMotion.slow,
        curve: AppMotion.curve,
        builder: (context, animated, _) => Container(
          height: height,
          decoration: BoxDecoration(
            color: trackColor ?? colors.surfaceHover,
            borderRadius: BorderRadius.circular(height),
          ),
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: animated,
            child: Container(
              decoration: BoxDecoration(
                color: color ?? colors.accent,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact progress ring, for a row's leading slot.
class AppProgressRing extends StatelessWidget {
  const AppProgressRing({required this.value, this.size = 18, this.strokeWidth = 2, super.key});

  final double value;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.clamp(0.0, 1.0),
          track: colors.borderStrong,
          fill: colors.accent,
          strokeWidth: strokeWidth,
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.track,
    required this.fill,
    required this.strokeWidth,
    required this.textDirection,
  });

  final double value;
  final Color track;
  final Color fill;
  final double strokeWidth;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(inset, 0, 2 * pi, false, paint..color = track);
    if (value <= 0) return;
    // Clockwise from the top in LTR, anticlockwise in RTL, so the ring fills the way text reads.
    final sweep = 2 * pi * value * (textDirection == TextDirection.rtl ? -1 : 1);
    canvas.drawArc(inset, -pi / 2, sweep, false, paint..color = fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}
