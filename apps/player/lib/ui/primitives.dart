import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/tokens.dart';

enum BadgeTone { neutral, accent, success, warning, danger }

/// A small status label. Used for state ("this device", "completed"), never for decoration.
class AppBadge extends StatelessWidget {
  const AppBadge({required this.label, this.icon, this.tone = BadgeTone.neutral, super.key});

  final String label;
  final IconData? icon;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (bg, fg) = switch (tone) {
      BadgeTone.neutral => (colors.surfaceHover, colors.textSecondary),
      BadgeTone.accent => (colors.accentSubtle, colors.accentText),
      BadgeTone.success => (colors.successSubtle, colors.success),
      BadgeTone.warning => (colors.warningSubtle, colors.warning),
      BadgeTone.danger => (colors.dangerSubtle, colors.danger),
    };

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.smAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: AppSpace.x1),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, height: 1.2, color: fg),
          ),
        ],
      ),
    );
  }
}

/// A bordered container for content that genuinely belongs together (a settings group, a dialog
/// body). Deliberately flat: a hairline, no shadow. Most content should not be in one of these.
class AppSurface extends StatelessWidget {
  const AppSurface({
    required this.child,
    this.padding,
    this.color,
    this.radius = AppRadius.lgAll,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: radius,
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

/// A square tile holding an icon, used as the leading mark of a row.
class IconTile extends StatelessWidget {
  const IconTile({required this.icon, this.size = 36, this.color, this.iconColor, super.key});

  final IconData icon;
  final double size;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? colors.surfaceRaised,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Icon(icon, size: size * 0.46, color: iconColor ?? colors.textSecondary),
    );
  }
}

/// A monogram: the first letter of a name in a quiet tile. Gives a course or a person a visual
/// anchor in a list without inventing imagery the catalogue does not have.
class Monogram extends StatelessWidget {
  const Monogram({required this.text, this.size = 40, this.circle = false, super.key});

  final String text;
  final double size;
  final bool circle;

  static String initialOf(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '·';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle
            ? null
            : BorderRadius.circular(size >= 40 ? AppRadius.md : AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        initialOf(text),
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          height: 1,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// The product mark: a play glyph in an accent square.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: CustomPaint(painter: _PlayGlyph(color: colors.onAccent)),
    );
  }
}

class _PlayGlyph extends CustomPainter {
  _PlayGlyph({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // A slightly rounded triangle, optically centred (nudged right of true centre).
    final path = Path()
      ..moveTo(w * 0.39, h * 0.30)
      ..lineTo(w * 0.70, h * 0.50)
      ..lineTo(w * 0.39, h * 0.70)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w * 0.06,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w * 0.06,
    );
  }

  @override
  bool shouldRepaint(_PlayGlyph old) => old.color != color;
}

/// Metadata items separated by a dot: "Teacher · 12 sessions · 4 h".
class MetaLine extends StatelessWidget {
  const MetaLine({required this.items, this.style, this.maxLines = 1, super.key});

  final List<String> items;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodySmall;
    return Text(
      items.where((i) => i.isNotEmpty).join('  ·  '),
      style: base,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A one-pixel rule.
class Hairline extends StatelessWidget {
  const Hairline({this.indent = 0, this.vertical = false, super.key});

  final double indent;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.border;
    if (vertical) return Container(width: 1, color: color);
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: Container(height: 1, color: color),
    );
  }
}

/// A keyboard key cap, for shortcut hints.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
