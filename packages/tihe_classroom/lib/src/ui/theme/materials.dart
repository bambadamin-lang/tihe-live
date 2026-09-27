import 'dart:math';

import 'package:flutter/material.dart';

import 'classroom_theme.dart';

/// Procedural materials — drawn, not loaded from images, so they stay sharp at any size and
/// cost no assets. Each is deterministic (seeded) and never repaints on its own.

/// A walnut desk top: long grain lines of varying darkness with the occasional knot.
class WoodGrainPainter extends CustomPainter {
  WoodGrainPainter(this.theme, {this.seed = 7});

  final ClassroomTheme theme;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.woodMid, theme.woodDark],
        ).createShader(rect),
    );
    final random = Random(seed);
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Boards run horizontally; each grain line wanders a little.
    for (var y = 0.0; y < size.height; y += 3 + random.nextDouble() * 5) {
      final dark = random.nextBool();
      grain
        ..strokeWidth = 0.6 + random.nextDouble() * 1.6
        ..color = (dark ? Colors.black : theme.woodLight).withValues(
          alpha: 0.05 + random.nextDouble() * (dark ? 0.12 : 0.1),
        );
      final path = Path()..moveTo(0, y);
      final amplitude = 1 + random.nextDouble() * 4;
      final wavelength = 180 + random.nextDouble() * 320;
      final phase = random.nextDouble() * pi * 2;
      for (var x = 0.0; x <= size.width; x += 24) {
        path.lineTo(x, y + sin(x / wavelength * pi * 2 + phase) * amplitude);
      }
      canvas.drawPath(path, grain);
    }
    // A few knots.
    for (var i = 0; i < (size.width * size.height / 400000).ceil(); i++) {
      final c = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      for (var r = 3.0; r < 22; r += 3.5) {
        canvas.drawOval(
          Rect.fromCenter(center: c, width: r * 3.2, height: r),
          grain
            ..strokeWidth = 1
            ..color = Colors.black.withValues(alpha: 0.1),
        );
      }
    }
    // Soft vignette, as if lit from above the desk.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.6),
          radius: 1.3,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.35),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(WoodGrainPainter old) =>
      old.seed != seed || old.theme != theme;
}

/// Brushed aluminium: a vertical sheen with fine horizontal brushing.
class BrushedMetalPainter extends CustomPainter {
  BrushedMetalPainter(this.theme, {this.radius = 14});

  final ClassroomTheme theme;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = theme.metal.createShader(Offset.zero & size),
    );
    final random = Random(3);
    final line = Paint()..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 1.5) {
      line.color = (random.nextBool() ? Colors.white : Colors.black).withValues(
        alpha: random.nextDouble() * 0.06,
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.restore();
    // Bevel: bright top edge, dark bottom edge.
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.35),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(BrushedMetalPainter old) =>
      old.radius != radius || old.theme != theme;
}

/// Cream paper with faint fibres.
class PaperPainter extends CustomPainter {
  PaperPainter(this.theme, {this.radius = 16, this.lined = false});

  final ClassroomTheme theme;
  final double radius;

  /// Notebook rules, for the chat.
  final bool lined;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = theme.paper.createShader(Offset.zero & size),
    );
    final random = Random(11);
    final fibre = Paint()..strokeWidth = 0.6;
    for (var i = 0; i < size.width * size.height / 900; i++) {
      final p = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final a = random.nextDouble() * pi;
      fibre.color = theme.inkSoft.withValues(alpha: random.nextDouble() * 0.05);
      canvas.drawLine(
        p,
        p + Offset(cos(a), sin(a)) * (2 + random.nextDouble() * 5),
        fibre,
      );
    }
    if (lined) {
      final rule = Paint()
        ..color = const Color(0xFF5B7FB5).withValues(alpha: 0.18)
        ..strokeWidth = 1;
      for (var y = 44.0; y < size.height; y += 28) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.radius != radius || old.lined != lined || old.theme != theme;
}

/// The desk: wood grain behind everything, painted once.
class WoodDesk extends StatelessWidget {
  const WoodDesk({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: WoodGrainPainter(ClassroomTheme.of(context)),
    isComplex: true,
    willChange: false,
    child: child,
  );
}
