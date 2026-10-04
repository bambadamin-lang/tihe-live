import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/tokens.dart';

/// Interaction state handed to a [Pressable] builder.
@immutable
class PressState {
  const PressState({
    required this.hovered,
    required this.pressed,
    required this.focused,
    required this.enabled,
  });

  final bool hovered;
  final bool pressed;

  /// Keyboard focus only. A mouse click does not show the ring, so it never flashes on every tap.
  final bool focused;
  final bool enabled;
}

/// The base of everything clickable.
///
/// One implementation of hover, press, keyboard focus and disabled, so a button, a list row and a
/// nav item all respond the same way: a quiet background shift on hover, a deeper one on press, and
/// an accent ring for keyboard focus. Enter and Space activate, as they should on desktop.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.onTap,
    this.child,
    this.builder,
    this.onDoubleTap,
    this.color = Colors.transparent,
    this.hoverColor,
    this.pressedColor,
    this.border,
    this.borderRadius = AppRadius.mdAll,
    this.padding,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.tooltip,
    this.showFocusRing = true,
    this.mouseCursor,
    super.key,
  }) : assert(child != null || builder != null, 'Provide a child or a builder.');

  /// Null disables.
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Widget? child;
  final Widget Function(BuildContext context, PressState state)? builder;
  final Color color;

  /// Defaults to the theme's hover surface.
  final Color? hoverColor;
  final Color? pressedColor;
  final BoxBorder? border;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final String? tooltip;
  final bool showFocusRing;
  final MouseCursor? mouseCursor;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap?.call()),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = PressState(
      hovered: _hovered && _enabled,
      pressed: _pressed && _enabled,
      focused: _focused && _enabled,
      enabled: _enabled,
    );

    final background = !state.enabled
        ? widget.color
        : state.pressed
        ? (widget.pressedColor ?? colors.surfacePressed)
        : state.hovered
        ? (widget.hoverColor ?? colors.surfaceHover)
        : widget.color;

    final content = widget.builder?.call(context, state) ?? widget.child!;

    Widget result = FocusableActionDetector(
      enabled: _enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      actions: _actions,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      mouseCursor:
          widget.mouseCursor ?? (_enabled ? SystemMouseCursors.click : SystemMouseCursors.basic),
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: background,
            borderRadius: widget.borderRadius,
            border: widget.border,
          ),
          foregroundDecoration: state.focused && widget.showFocusRing
              ? BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: Border.all(color: colors.accent, width: 2),
                )
              : null,
          child: content,
        ),
      ),
    );

    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip, child: result);
    }

    return Semantics(button: true, enabled: _enabled, label: widget.semanticLabel, child: result);
  }
}
