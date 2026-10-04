import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/gateway_client.dart';
import 'classroom_theme.dart';
import 'glass.dart';

/// The TIHE Live mark: two play wedges, one behind the other, lit from the top — a class going
/// out live. Drawn rather than bundled, so it is sharp at any size and in both themes.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _MarkPainter(ClassroomTheme.of(context))),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.theme);

  final ClassroomTheme theme;

  Path _wedge(Rect box, double radius) {
    // A play triangle pointing to the physical right, its corners rounded.
    final a = box.topLeft, b = box.centerRight, c = box.bottomLeft;
    Offset toward(Offset from, Offset to) =>
        from + (to - from) / (to - from).distance * radius;
    return Path()
      ..moveTo(toward(a, b).dx, toward(a, b).dy)
      ..lineTo(toward(b, a).dx, toward(b, a).dy)
      ..quadraticBezierTo(b.dx, b.dy, toward(b, c).dx, toward(b, c).dy)
      ..lineTo(toward(c, b).dx, toward(c, b).dy)
      ..quadraticBezierTo(c.dx, c.dy, toward(c, a).dx, toward(c, a).dy)
      ..lineTo(toward(a, c).dx, toward(a, c).dy)
      ..quadraticBezierTo(a.dx, a.dy, toward(a, b).dx, toward(a, b).dy)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final back = _wedge(
      Rect.fromLTWH(s * 0.04, s * 0.14, s * 0.62, s * 0.72),
      s * 0.1,
    );
    final front = _wedge(
      Rect.fromLTWH(s * 0.3, s * 0.06, s * 0.66, s * 0.88),
      s * 0.11,
    );
    canvas
      ..drawPath(
        front,
        Paint()
          ..color = theme.accent.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.08),
      )
      ..drawPath(
        back,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, s * 0.14),
            Offset(0, s * 0.86),
            const [Color(0xFF1E4FD8), Color(0xFF3A3FC9)],
          ),
      )
      ..drawPath(
        front,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(s * 0.3, s * 0.06),
            Offset(s * 0.9, s * 0.94),
            const [Color(0xFF6FD3FF), Color(0xFF2F6FFE), Color(0xFF2448E0)],
            const [0, 0.55, 1],
          ),
      );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.theme != theme;
}

/// The mark and the name, as the app's title bar shows them.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.compact = false});

  /// The mark alone, for phones.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    // The name is Latin: it reads left to right whatever the page's direction.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Semantics(
        label: 'TIHE Live',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 30),
            if (!compact) ...[
              const SizedBox(width: 9),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'TIHE',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: ' Live',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: t.text.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontSize: 19,
                  height: 1.1,
                  letterSpacing: -0.2,
                  color: t.text,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A lamp in a pill: a dot and a word, the dot breathing while the state is in flux.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.color,
    required this.label,
    this.pulsing = false,
  });

  final Color color;
  final String label;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPill(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: pulsing
          ? PulsingDot(color: color, size: 8)
          : StatusDot(color: color, size: 8),
      child: Text(label, style: TextStyle(color: t.textSecondary)),
    );
  }
}

/// The connection lamp: green and "online" while the class's link is up.
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, required this.status});

  final GatewayStatus status;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final (color, label) = switch (status) {
      GatewayStatus.online => (t.success, 'آنلاین'),
      GatewayStatus.connecting => (t.warning, 'در حال اتصال'),
      GatewayStatus.reconnecting => (t.warning, 'اتصال دوباره…'),
      GatewayStatus.closed => (t.danger, 'قطع'),
    };
    return StatusPill(
      color: color,
      label: label,
      pulsing: status != GatewayStatus.online,
    );
  }
}

/// How a desktop app that draws its own window frame joins the classroom's top bar: its window
/// buttons go at the bar's physical right edge, and dragging the bar moves the window.
///
/// Provide one above the page (the example app does on Windows, with window_manager). Without
/// one, the platform's own title bar is in charge and the classroom draws none.
class WindowChrome extends InheritedWidget {
  const WindowChrome({
    super.key,
    required this.controls,
    required this.dragArea,
    required super.child,
  });

  /// Minimise, maximise and close.
  final Widget controls;

  /// Wraps a bar so that dragging it moves the window (and double-clicking maximises it).
  final Widget Function(Widget bar) dragArea;

  static WindowChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowChrome>();

  @override
  bool updateShouldNotify(WindowChrome old) =>
      old.controls != controls || old.dragArea != dragArea;
}

/// Window buttons in the classroom's style: quiet glyphs that light on hover, red for close.
class WindowButtons extends StatelessWidget {
  const WindowButtons({
    super.key,
    required this.onMinimise,
    required this.onMaximise,
    required this.onClose,
    this.maximised = false,
  });

  final VoidCallback onMinimise;
  final VoidCallback onMaximise;
  final VoidCallback onClose;
  final bool maximised;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback onTap, {
      bool close = false,
    }) => GlassPressable(
      onTap: onTap,
      tooltip: tooltip,
      semanticLabel: tooltip,
      radius: 10,
      builder: (context, s) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 42,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: s.hovered
              ? (close ? t.danger : t.glassHover)
              : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 17,
          color: s.hovered ? (close ? Colors.white : t.text) : t.textSecondary,
        ),
      ),
    );
    // Windows puts these at the physical right in every language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(ClassroomIcons.minimiseWindow, 'کوچک کردن', onMinimise),
          const SizedBox(width: 4),
          button(
            ClassroomIcons.maximiseWindow,
            maximised ? 'بازگرداندن' : 'بزرگ کردن پنجره',
            onMaximise,
          ),
          const SizedBox(width: 4),
          button(ClassroomIcons.closeWindow, 'بستن', onClose, close: true),
        ],
      ),
    );
  }
}
