import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/persian.dart';
import 'classroom_theme.dart';

/// The classroom's controls, in frosted glass. Each layer (stage, pods, bars, sheets) is a pane
/// over the canvas; state is carried by tint and icon, never by bevels or texture.

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
  static const endClass = LucideIcons.circleStop;
  static const leave = LucideIcons.logOutDir;
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
  static const join = LucideIcons.logInDir;

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

/// The canvas behind everything: a near-flat colour with three soft glows, painted once.
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
      painter: _GlowPainter(t),
      isComplex: true,
      willChange: false,
      child: BackdropGroup(child: child),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.theme);

  final ClassroomTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = theme.canvas);
    final longest = size.longestSide;
    void glow(Alignment at, double radius, Color color) {
      final center = at.alongSize(size);
      canvas.drawCircle(
        center,
        longest * radius,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(
                Rect.fromCircle(center: center, radius: longest * radius),
              ),
      );
    }

    glow(const Alignment(0.85, -0.95), 0.55, theme.glows[0]);
    glow(const Alignment(-0.9, 0.9), 0.5, theme.glows[1]);
    glow(const Alignment(0.1, 1.1), 0.35, theme.glows[2]);
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.theme != theme;
}

/// A pane of frosted glass: blur, a translucent fill, a lit rim and one soft shadow.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 16,
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

/// A pod: a glass pane with a quiet header, and — for video — an inset dark screen.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.inset = false,
    this.padding = 8,
  });

  final Widget child;
  final String? title;
  final IconData? icon;
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
              height: 30,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 6,
                  end: 2,
                  bottom: 4,
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 14, color: t.textTertiary),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.textSecondary,
                        ),
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
                    borderRadius: BorderRadius.circular(11),
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
    this.radius = 18,
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

/// A small glass capsule: the class title, status, counts.
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.leading,
    this.padding,
    this.fill,
  });

  final Widget child;
  final Widget? leading;
  final EdgeInsetsGeometry? padding;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Glass(
      radius: 999,
      shadow: false,
      fill: fill,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: t.text,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 7)],
            Flexible(child: child),
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
                  color: color.withValues(alpha: 0.55),
                  blurRadius: size,
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
    this.disabledCursor = SystemMouseCursors.basic,
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
      mouseCursor: enabled ? SystemMouseCursors.click : widget.disabledCursor,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 90),
          scale: state.pressed ? 0.96 : 1,
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      selected: selected,
      radius: 8,
      builder: (context, s) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: selected
              ? t.accentSubtle
              : s.pressed
              ? t.glassPressed
              : s.hovered
              ? t.glassHover
              : Colors.transparent,
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

/// A dock button: a rounded glass key with its label beneath.
///
/// [tint] colours the key for a state (off, raised hand) or a role (end class). A [solid] key is
/// filled with its tint, for the one destructive action in the dock.
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
    this.disabledCursor = SystemMouseCursors.basic,
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
        final Color bg;
        final Color fg;
        if (!s.enabled) {
          bg = t.glass;
          fg = t.textDisabled;
        } else if (solid && tint != null) {
          bg = s.hovered ? Color.lerp(tint, Colors.white, 0.12)! : tint!;
          fg = Colors.white;
        } else if (tint != null) {
          bg = tint!.withValues(alpha: s.hovered ? 0.3 : 0.2);
          fg = tint!;
        } else {
          bg = s.hovered ? t.glassHover : t.glass;
          fg = t.text;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 46,
                  height: 42,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: tint != null && s.enabled
                          ? tint!.withValues(alpha: solid ? 0 : 0.35)
                          : t.edgeLow,
                    ),
                  ),
                  child: Icon(icon, size: 19, color: fg),
                ),
                if (badge != null)
                  PositionedDirectional(
                    top: -5,
                    end: -5,
                    child: CountBadge(text: badge!, color: tint ?? t.accent),
                  ),
              ],
            ),
            if (showLabel) ...[
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: s.enabled ? t.textSecondary : t.textDisabled,
                ),
              ),
            ],
          ],
        );
      },
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
    );
  }
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
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(6),
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
  });

  final String title;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Glass(
          radius: 20,
          strong: true,
          overlay: true,
          padding: const EdgeInsets.fromLTRB(20, 14, 14, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                  ),
                  GlassIconButton(
                    icon: ClassroomIcons.close,
                    tooltip: 'بستن',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 14,
                      height: 1.6,
                    ),
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A segmented switch between a few options — the phone stage's pod tabs.
class GlassTabs<T> extends StatelessWidget {
  const GlassTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<({T value, String label, IconData? icon})> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Glass(
      radius: 14,
      shadow: false,
      padding: const EdgeInsets.all(3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in options)
              GlassPressable(
                onTap: () => onSelected(o.value),
                semanticLabel: o.label,
                selected: o.value == selected,
                radius: 11,
                builder: (context, s) {
                  final on = o.value == selected;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: on
                          ? (t.isDark ? t.glassPressed : Colors.white)
                          : s.hovered
                          ? t.glassHover
                          : Colors.transparent,
                      boxShadow: on && !t.isDark ? t.lifted : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (o.icon != null) ...[
                          Icon(
                            o.icon,
                            size: 15,
                            color: on ? t.accentText : t.textTertiary,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          o.label,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: on ? t.text : t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
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
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: ClassroomTheme.of(context).hairline,
  );
}
