import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/persian.dart';
import 'classroom_theme.dart';
import 'cursor.dart';
import 'motion.dart';

/// The classroom's controls, in frosted glass. Each layer (stage, pods, bars, sheets) is a pane
/// over the sky; state is carried by tint and icon, never by bevels or texture.

/// Every icon the classroom uses: one family (Lucide, as in the player), one weight.
abstract final class ClassroomIcons {
  static const mic = LucideIcons.mic;
  static const micOff = LucideIcons.micOff;
  static const camera = LucideIcons.video;
  static const cameraOff = LucideIcons.videoOff;
  static const screenShare = LucideIcons.screenShare;
  static const screenShareOff = LucideIcons.screenShareOff;
  static const hand = LucideIcons.hand;
  static const lowerHand = LucideIcons.handMetal;
  static const layout = LucideIcons.layoutDashboard;
  static const settings = LucideIcons.slidersHorizontal;
  static const endClass = LucideIcons.circleDot;
  static const leave = LucideIcons.phoneOff;
  static const people = LucideIcons.usersRound;
  static const person = LucideIcons.userRound;
  static const gallery = LucideIcons.layoutGrid;
  static const screen = LucideIcons.monitor;
  static const window = LucideIcons.appWindow;
  static const whiteboard = LucideIcons.presentation;
  static const chat = LucideIcons.messageSquare;
  static const send = LucideIcons.sendHorizontalDir;
  static const close = LucideIcons.x;
  static const maximise = LucideIcons.maximize2;
  static const restore = LucideIcons.minimize2;
  static const more = LucideIcons.ellipsisVertical;
  static const moreHorizontal = LucideIcons.ellipsis;
  static const lock = LucideIcons.lock;
  static const check = LucideIcons.check;
  static const edit = LucideIcons.pencilRuler;
  static const muteAll = LucideIcons.micOff;
  static const lowerAll = LucideIcons.listX;
  static const light = LucideIcons.sun;
  static const dark = LucideIcons.moon;
  static const captureBlocked = LucideIcons.monitorOff;
  static const classEnded = LucideIcons.doorOpen;
  static const resize = LucideIcons.moveDiagonal;
  static const play = LucideIcons.play;
  static const join = LucideIcons.cornerDownLeft;
  static const course = LucideIcons.bookOpen;
  static const signal = LucideIcons.signalHigh;
  static const pin = LucideIcons.pin;
  static const reactions = LucideIcons.smile;
  static const emoji = LucideIcons.smilePlus;
  static const chevronDown = LucideIcons.chevronDown;
  static const previous = LucideIcons.chevronLeftDir;
  static const next = LucideIcons.chevronRightDir;
  static const server = LucideIcons.database;
  static const link = LucideIcons.link;
  static const hash = LucideIcons.hash;
  static const key = LucideIcons.keyRound;
  static const assistant = LucideIcons.usersRound;
  static const minimiseWindow = LucideIcons.minus;
  static const maximiseWindow = LucideIcons.square;
  static const closeWindow = LucideIcons.x;
  static const alert = LucideIcons.circleAlert;

  // Whiteboard.
  static const pen = LucideIcons.pen;
  static const marker = LucideIcons.brush;
  static const highlighter = LucideIcons.highlighter;
  static const line = LucideIcons.minus;
  static const arrow = LucideIcons.moveUpRight;
  static const rect = LucideIcons.square;
  static const ellipse = LucideIcons.circle;
  static const text = LucideIcons.type;
  static const eraser = LucideIcons.eraser;
  static const laser = LucideIcons.pointer;
  static const undo = LucideIcons.undo2;
  static const redo = LucideIcons.redo2;
  static const fill = LucideIcons.paintBucket;
  static const noFill = LucideIcons.squareDashed;
  static const width = LucideIcons.chartNoAxesColumnIncreasing;
  static const newPage = LucideIcons.filePlus2;
  static const clearPage = LucideIcons.brushCleaning;
  static const previousPage = LucideIcons.chevronLeftDir;
  static const nextPage = LucideIcons.chevronRightDir;
}

/// The sky behind everything, painted once: a navy gradient, a few soft glows, two planets lit
/// along their inner rims at the edges and faint orbits around them.
///
/// Also establishes the [BackdropGroup] that the stage's panes share, so a stage of seven pods
/// costs one blur, not seven.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return CustomPaint(
      painter: SkyPainter(t),
      isComplex: true,
      willChange: false,
      child: BackdropGroup(child: child),
    );
  }
}

class SkyPainter extends CustomPainter {
  SkyPainter(this.theme);

  final ClassroomTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final t = theme;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [t.canvasTop, t.canvas],
          const [0, 0.55],
        ),
    );
  }

  @override
  bool shouldRepaint(SkyPainter old) => old.theme != theme;
}

/// A pane of frosted glass: blur, a translucent fill, a lit rim and one soft shadow.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding,
    this.strong = false,
    this.fill,
    this.overlay = false,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  /// More body, for sheets and menus over busy content.
  final bool strong;

  /// Replaces the fill, e.g. a tint for a state.
  final Color? fill;

  /// Floats over other glass (toasts, sheets). Grouped blurs must not overlap, so an overlay
  /// blurs on its own.
  final bool overlay;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final shape = BorderRadius.circular(radius);
    final filter = ui.ImageFilter.blur(
      sigmaX: strong ? t.blur * 1.5 : t.blur,
      sigmaY: strong ? t.blur * 1.5 : t.blur,
    );
    final grouped = !overlay && BackdropGroup.of(context) != null;
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? (strong ? t.glassStrong : t.glass),
        borderRadius: shape,
      ),
      position: DecorationPosition.background,
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow ? t.floating : null,
      ),
      child: CustomPaint(
        foregroundPainter: _RimPainter(t.rim, radius),
        child: ClipRRect(
          borderRadius: shape,
          child: grouped
              ? BackdropFilter.grouped(filter: filter, child: body)
              : BackdropFilter(filter: filter, child: body),
        ),
      ),
    );
  }
}

/// A one-pixel rim drawn with a gradient, lit along the top edge like real glass.
class _RimPainter extends CustomPainter {
  _RimPainter(this.gradient, this.radius);

  final Gradient gradient;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.gradient != gradient || old.radius != radius;
}

/// A pod: a glass pane with a header — icon, title, an optional count — and, for video, an
/// inset dark screen.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.count,
    this.trailing,
    this.inset = false,
    this.padding = 12,
  });

  final Widget child;
  final String? title;
  final IconData? icon;

  /// Shown after the title, in parentheses: how many people or hands.
  final int? count;
  final Widget? trailing;

  /// Show the content on an inset dark screen (video) rather than on the glass itself.
  final bool inset;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Glass(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            SizedBox(
              height: 34,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: t.textSecondary),
                      const SizedBox(width: 9),
                    ],
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: t.text,
                              ),
                            ),
                          ),
                          if (count != null) ...[
                            const SizedBox(width: 6),
                            RollingText(
                              '(${toPersianDigits(count!)})',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: t.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          Expanded(
            child: inset
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(color: t.screen, child: child),
                  )
                : child,
          ),
        ],
      ),
    );
  }
}

/// A glass bar, for the top bar, the control dock and tool trays.
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Glass(
    radius: radius,
    padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: child,
  );
}

/// A small glass chip: the class title, the clock, status lamps.
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.leading,
    this.trailing,
    this.padding,
    this.fill,
    this.radius = 14,
  });

  final Widget child;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Glass(
      radius: radius,
      shadow: false,
      fill: fill,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: t.text,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Flexible(child: child),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// A status dot with a soft halo when on.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.color,
    this.on = true,
    this.size = 8,
  });

  final Color color;
  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? color : t.textDisabled,
        boxShadow: on
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: size * 1.2,
                ),
              ]
            : null,
      ),
    );
  }
}

/// A dot that breathes — for "live" and "recording".
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.4, end: 1.0).animate(_controller),
    child: StatusDot(color: widget.color, size: widget.size),
  );
}

/// Hover, press, keyboard focus and disabled for anything clickable in the classroom — one
/// implementation, so every control responds the same way.
class GlassPressable extends StatefulWidget {
  const GlassPressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.semanticLabel,
    this.tooltip,
    this.toggled,
    this.selected,
    this.radius = 12,
    this.disabledCursor = GlowCursors.basic,
  });

  /// Null disables.
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, GlassState state) builder;
  final String? semanticLabel;
  final String? tooltip;
  final bool? toggled;
  final bool? selected;
  final double radius;
  final MouseCursor disabledCursor;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

/// Interaction state handed to a [GlassPressable] builder.
typedef GlassState = ({bool hovered, bool pressed, bool focused, bool enabled});

class _GlassPressableState extends State<GlassPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => widget.onTap?.call(),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final enabled = widget.onTap != null;
    final state = (
      hovered: _hovered && enabled,
      pressed: _pressed && enabled,
      focused: _focused && enabled,
      enabled: enabled,
    );
    Widget result = FocusableActionDetector(
      enabled: enabled,
      actions: _actions,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      mouseCursor: enabled ? GlowCursors.click : widget.disabledCursor,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        // Quick down, a small spring back up: the key feels pressed, not just recoloured.
        child: AnimatedScale(
          duration: Motion.of(
            context,
            state.pressed ? const Duration(milliseconds: 90) : Motion.medium,
          ),
          curve: state.pressed ? Curves.easeOut : Curves.easeOutBack,
          scale: state.pressed ? 0.95 : 1,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              border: state.focused
                  ? Border.all(color: t.accent, width: 2)
                  : null,
            ),
            child: widget.builder(context, state),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip, child: result);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: widget.toggled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: result,
    );
  }
}

/// A compact icon button for headers and trays.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 30,
    this.iconSize = 16,
    this.selected = false,
    this.color,
    this.fill,
    this.radius = 9,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool selected;
  final Color? color;

  /// A resting background, for buttons that float over video.
  final Color? fill;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      selected: selected,
      radius: radius,
      builder: (context, s) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: selected
              ? t.accentSubtle
              : s.pressed
              ? t.glassPressed
              : s.hovered
              ? (fill != null
                    ? Color.alphaBlend(t.glassHover, fill!)
                    : t.glassHover)
              : fill ?? Colors.transparent,
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: !s.enabled
              ? t.textDisabled
              : selected
              ? t.accentText
              : color ?? (s.hovered ? t.text : t.textSecondary),
        ),
      ),
    );
  }
}

/// The primary action: the accent as a gradient with a soft glow, full width by default.
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 50,
    this.color,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  /// A flat colour instead of the accent gradient (red for a destructive confirm).
  final Color? color;

  /// Shows a spinner in place of the icon.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final direction = Directionality.of(context);
    return GlassPressable(
      onTap: onPressed,
      semanticLabel: label,
      radius: 14,
      builder: (context, s) {
        final enabled = s.enabled;
        return AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: !enabled
                ? t.field
                : color == null
                ? null
                : (s.hovered ? Color.lerp(color, Colors.white, 0.1) : color),
            gradient: enabled && color == null
                ? t.accentGradient(direction)
                : null,
            border: enabled
                ? Border.all(color: Colors.white.withValues(alpha: 0.14))
                : Border.all(color: t.fieldBorder),
            boxShadow: enabled
                ? (color == null
                      ? t.accentGlow(strength: s.hovered ? 1.4 : 1)
                      : [
                          BoxShadow(
                            color: color!.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ])
                : null,
          ),
          foregroundDecoration: enabled && s.hovered && color == null
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0.07),
                )
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: enabled ? t.onAccent : t.textDisabled,
                  ),
                )
              else if (icon != null)
                Icon(
                  icon,
                  size: 20,
                  color: enabled ? t.onAccent : t.textDisabled,
                ),
              if (busy || icon != null) const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: enabled ? t.onAccent : t.textDisabled,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// An icon on a small rounded tile of deep accent: the mark of a card or a sheet.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.size = 52,
    this.color,
    this.solid = false,
  });

  final IconData icon;
  final double size;

  /// Tints the tile for a state (red for an alert); the accent otherwise.
  final Color? color;

  /// Filled with the accent gradient, for the brand's own mark.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final tint = color ?? t.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: solid
            ? t.accentGradient(Directionality.of(context))
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tint.withValues(alpha: t.isDark ? 0.3 : 0.16),
                  tint.withValues(alpha: t.isDark ? 0.14 : 0.08),
                ],
              ),
        border: Border.all(
          color: solid
              ? Colors.white.withValues(alpha: 0.18)
              : tint.withValues(alpha: 0.32),
        ),
        boxShadow: solid ? t.accentGlow(strength: 0.8) : null,
      ),
      child: Icon(
        icon,
        size: size * 0.46,
        color: solid
            ? t.onAccent
            : color ?? (t.isDark ? t.accentText : t.accent),
      ),
    );
  }
}

/// A dock key: an icon with its label beneath, flat on the dock until hovered.
///
/// [tint] colours the key for a state (off, raised hand, open panel). A [solid] key is a filled
/// tile of its tint, for the one destructive action in the dock.
class DockButton extends StatelessWidget {
  const DockButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tint,
    this.solid = false,
    this.showLabel = true,
    this.tooltip,
    this.toggled,
    this.badge,
    this.disabledCursor = GlowCursors.basic,
    this.wave = false,
    this.width = 78,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? tint;
  final bool solid;
  final bool showLabel;
  final String? tooltip;
  final bool? toggled;
  final String? badge;
  final MouseCursor disabledCursor;

  /// Waves the icon once each time this turns true — the hand going up.
  final bool wave;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      onTap: onPressed,
      tooltip: tooltip ?? label,
      semanticLabel: label,
      toggled: toggled,
      radius: 14,
      disabledCursor: disabledCursor,
      builder: (context, s) {
        final Color fg;
        final Color keyColor;
        if (!s.enabled) {
          fg = t.textDisabled;
          keyColor = Colors.transparent;
        } else if (solid && tint != null) {
          fg = Colors.white;
          keyColor = s.hovered ? Color.lerp(tint, Colors.white, 0.12)! : tint!;
        } else if (tint != null) {
          fg = tint!;
          keyColor = tint!.withValues(alpha: s.hovered ? 0.26 : 0.16);
        } else {
          fg = t.text;
          keyColor = s.hovered ? t.glassHover : Colors.transparent;
        }
        final key = AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.enter,
          width: solid ? 46 : 44,
          height: solid ? 40 : 36,
          // Hovered keys rise a little off the dock.
          transform: Matrix4.translationValues(
            0,
            s.hovered && !Motion.reduced(context) ? -2 : 0,
            0,
          ),
          decoration: BoxDecoration(
            color: keyColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: solid && s.enabled && tint != null
                ? [
                    BoxShadow(
                      color: tint!.withValues(alpha: s.hovered ? 0.5 : 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: _Wave(
            active: wave,
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.6, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: Icon(
                icon,
                key: ValueKey((icon, fg)),
                size: solid ? 21 : 23,
                color: fg,
              ),
            ),
          ),
        );
        return SizedBox(
          width: showLabel ? width : 46,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  key,
                  PositionedDirectional(
                    top: -5,
                    end: -6,
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.medium),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Motion.exit,
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: badge == null
                          ? const SizedBox.shrink()
                          : CountBadge(
                              key: ValueKey(badge),
                              text: badge!,
                              color: tint ?? t.accent,
                            ),
                    ),
                  ),
                ],
              ),
              if (showLabel) ...[
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: s.enabled
                        ? (tint != null && !solid ? tint : t.textSecondary)
                        : t.textDisabled,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The dock's leave key: a red slab with the icon and word on it, at the start of the dock.
class LeaveButton extends StatelessWidget {
  const LeaveButton({super.key, required this.onPressed, this.compact = false});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      onTap: onPressed,
      tooltip: 'خروج از کلاس',
      semanticLabel: 'خروج',
      radius: 16,
      builder: (context, s) => AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        width: compact ? 50 : 84,
        height: compact ? 42 : 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(t.danger, Colors.white, s.hovered ? 0.16 : 0.08)!,
              t.danger,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: t.danger.withValues(alpha: s.hovered ? 0.5 : 0.32),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(ClassroomIcons.leave, size: 20, color: Colors.white),
            if (!compact) ...[
              const SizedBox(height: 4),
              const Text(
                'خروج',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A key and a small chevron beside it in one outlined group — microphone and camera, whose
/// chevron picks the device.
class SplitDockButton extends StatelessWidget {
  const SplitDockButton({
    super.key,
    required this.main,
    required this.onMore,
    required this.moreTooltip,
  });

  final Widget main;
  final VoidCallback? onMore;
  final String moreTooltip;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: t.field,
        border: Border.all(color: t.fieldBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          main,
          if (onMore != null)
            GlassIconButton(
              icon: ClassroomIcons.chevronDown,
              tooltip: moreTooltip,
              size: 26,
              iconSize: 15,
              onPressed: onMore,
            ),
        ],
      ),
    );
  }
}

/// A media toggle for microphone, camera and screen share. Off is tinted and crossed out, so a
/// muted microphone is never mistaken for a live one; a locked toggle shows a padlock instead
/// of pretending to work.
class MediaToggle extends StatelessWidget {
  const MediaToggle({
    super.key,
    required this.on,
    required this.icon,
    required this.offIcon,
    required this.label,
    this.onPressed,
    this.locked = false,
    this.showLabel = true,
  });

  final bool on;
  final IconData icon;
  final IconData offIcon;
  final String label;
  final VoidCallback? onPressed;

  /// The class does not allow this right now (no capability).
  final bool locked;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final blocked = locked && !on;
    return DockButton(
      icon: blocked ? ClassroomIcons.lock : (on ? icon : offIcon),
      label: label,
      showLabel: showLabel,
      toggled: on,
      width: 66,
      tooltip: blocked ? '$label — نیاز به اجازهٔ میزبان' : label,
      tint: blocked || on ? null : t.danger,
      disabledCursor: SystemMouseCursors.forbidden,
      onPressed: blocked ? null : onPressed,
    );
  }
}

/// The raise-hand key. Raised, it turns amber and shows the place in the queue.
class HandToggle extends StatelessWidget {
  const HandToggle({
    super.key,
    required this.raised,
    required this.onPressed,
    this.queuePosition,
    this.showLabel = true,
  });

  final bool raised;
  final VoidCallback? onPressed;

  /// 1-based place in the hand queue, shown while raised.
  final int? queuePosition;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final label = raised ? 'پایین آوردن دست' : 'بالا بردن دست';
    return DockButton(
      icon: ClassroomIcons.hand,
      label: raised ? 'دست بالاست' : 'دست',
      showLabel: showLabel,
      toggled: raised,
      tooltip: onPressed == null ? 'میزبان بالا بردن دست را بسته است' : label,
      tint: raised ? t.warning : null,
      badge: raised && queuePosition != null
          ? toPersianDigits(queuePosition!)
          : null,
      disabledCursor: SystemMouseCursors.forbidden,
      onPressed: onPressed,
      wave: raised,
    );
  }
}

/// Plays a short wave on its child each time [active] turns true.
class _Wave extends StatefulWidget {
  const _Wave({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(_Wave old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !Motion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final v = _controller.value;
      if (v == 0 || v == 1) return child!;
      // Three swings that die away, pivoting at the wrist.
      final angle = math.sin(v * math.pi * 3) * 0.35 * (1 - v);
      return Transform.rotate(
        angle: angle,
        alignment: const Alignment(0, 0.8),
        child: child,
      );
    },
  );
}

/// A small count on a control: the place in the hand queue.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18),
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: ClassroomTheme.of(context).canvas, width: 1.5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10.5,
        height: 1.1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// A role label next to a name: a tinted tag, quiet enough to sit in a busy list.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// A glass dialog for menus, pickers and confirmations.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.title,
    required this.child,
    this.width = 460,
    this.icon,
    this.iconColor,
  });

  final String title;
  final Widget child;
  final double width;

  /// A tile beside the title, for sheets that confirm something.
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Glass(
          radius: 24,
          strong: true,
          overlay: true,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    IconTile(icon: icon!, size: 40, color: iconColor),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  GlassIconButton(
                    icon: ClassroomIcons.close,
                    tooltip: 'بستن',
                    fill: t.field,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A segmented switch between a few options — the phone stage's pod tabs, the launcher's roles.
/// The chosen segment is filled with the accent.
class GlassTabs<T> extends StatelessWidget {
  const GlassTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.expand = false,
  });

  final List<({T value, String label, IconData? icon})> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// Share the width equally rather than scroll.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final direction = Directionality.of(context);
    Widget segment(({T value, String label, IconData? icon}) o) =>
        GlassPressable(
          onTap: () => onSelected(o.value),
          semanticLabel: o.label,
          selected: o.value == selected,
          radius: 12,
          builder: (context, s) {
            final on = o.value == selected;
            return AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: expand ? 12 : 9,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: on ? t.accentGradient(direction) : null,
                color: on
                    ? null
                    : s.hovered
                    ? t.glassHover
                    : Colors.transparent,
                boxShadow: on ? t.accentGlow(strength: 0.6) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (o.icon != null) ...[
                    Icon(
                      o.icon,
                      size: 17,
                      color: on ? t.onAccent : t.textSecondary,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      o.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? t.onAccent : t.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );

    final box = BoxDecoration(
      borderRadius: BorderRadius.circular(15),
      color: t.field,
      border: Border.all(color: t.fieldBorder),
    );
    if (expand) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: box,
        child: Row(
          children: [
            for (final (i, o) in options.indexed) ...[
              if (i > 0)
                // A hairline between two unchosen segments only.
                Container(
                  width: 1,
                  height: 22,
                  color: o.value == selected || options[i - 1].value == selected
                      ? Colors.transparent
                      : t.hairline,
                ),
              Expanded(child: segment(o)),
            ],
          ],
        ),
      );
    }
    return Glass(
      radius: 15,
      shadow: false,
      padding: const EdgeInsets.all(3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (final o in options) segment(o)],
        ),
      ),
    );
  }
}

/// A short vertical rule between groups in a bar.
class BarDivider extends StatelessWidget {
  const BarDivider({super.key, this.height = 28});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: height,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: ClassroomTheme.of(context).hairline,
  );
}
