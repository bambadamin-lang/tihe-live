import 'package:flutter/material.dart';

import 'classroom_theme.dart';
import 'cursor.dart';
import 'glass.dart';
import 'motion.dart';

/// Glass menus and popovers that open beside the control that asked for them: the dock's
/// "more", the device pickers, a person's actions, the emoji tray.
///
/// Material's popup menus are not used: their barrier would put the system arrow back under the
/// pointer, and their surface is not glass.

/// One line of a [showGlassMenu].
sealed class GlassMenuEntry<T> {
  const GlassMenuEntry();
}

class GlassMenuItem<T> extends GlassMenuEntry<T> {
  const GlassMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.checked = false,
    this.danger = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// A tick at the end: the current device, the current layout.
  final bool checked;
  final bool danger;
  final bool enabled;
}

class GlassMenuDivider<T> extends GlassMenuEntry<T> {
  const GlassMenuDivider();
}

/// A quiet caption over the items that follow.
class GlassMenuLabel<T> extends GlassMenuEntry<T> {
  const GlassMenuLabel(this.text);

  final String text;
}

/// Opens a menu next to [context]'s widget and returns the chosen value, or null if dismissed.
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required List<GlassMenuEntry<T>> entries,
  double? width = 240,
}) => showGlassPopover<T>(
  context: context,
  width: width,
  builder: (context) => _GlassMenu<T>(entries: entries),
);

/// Opens [builder]'s content in a glass card next to [context]'s widget: below it when there is
/// room, above it otherwise, aligned to its start edge. A null [width] matches the widget's.
Future<T?> showGlassPopover<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? width,
  EdgeInsetsGeometry padding = const EdgeInsets.all(6),
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final box = context.findRenderObject()! as RenderBox;
  final overlay = navigator.context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push(
    _PopoverRoute<T>(
      anchor: anchor,
      width: width ?? anchor.width,
      direction: Directionality.of(context),
      duration: Motion.of(context, Motion.medium),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (context) => themes.wrap(
        Glass(
          radius: 16,
          strong: true,
          overlay: true,
          padding: padding,
          child: Builder(builder: builder),
        ),
      ),
    ),
  );
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.width,
    required this.direction,
    required this.duration,
    required this.builder,
    required this.barrierLabel,
  });

  final Rect anchor;
  final double width;
  final TextDirection direction;
  final Duration duration;
  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration * 0.6;

  /// Whether the card opened above its anchor, so it grows from the anchor's side.
  bool _above = false;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Directionality(
    textDirection: direction,
    child: Stack(
      children: [
        // Covers the barrier, which would show the system arrow: a tap here closes the menu.
        Positioned.fill(
          child: MouseRegion(
            cursor: GlowCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        CustomSingleChildLayout(
          delegate: _PopoverLayout(
            anchor: anchor,
            width: width,
            direction: direction,
            placed: (above) => _above = above,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: builder(context),
          ),
        ),
      ],
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Motion.enter,
      reverseCurve: Motion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        child: child,
        builder: (context, child) {
          final v = curved.value;
          return Transform.translate(
            offset: Offset(0, (_above ? 8 : -8) * (1 - v)),
            child: child,
          );
        },
      ),
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout({
    required this.anchor,
    required this.width,
    required this.direction,
    required this.placed,
  });

  final Rect anchor;
  final double width;
  final TextDirection direction;
  final ValueChanged<bool> placed;

  static const _gap = 8.0;
  static const _margin = 10.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: width.clamp(0, constraints.maxWidth - 2 * _margin),
        maxWidth: width.clamp(0, constraints.maxWidth - 2 * _margin),
        maxHeight: constraints.maxHeight - 2 * _margin,
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final below = anchor.bottom + _gap;
    final fitsBelow = below + child.height <= size.height - _margin;
    final above = !fitsBelow && anchor.top - _gap - child.height >= _margin;
    placed(above);
    final y = above
        ? anchor.top - _gap - child.height
        : below.clamp(_margin, size.height - _margin - child.height);
    final x = direction == TextDirection.rtl
        ? anchor.right - child.width
        : anchor.left;
    return Offset(
      x.clamp(_margin, size.width - _margin - child.width),
      y.toDouble(),
    );
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.anchor != anchor || old.width != width || old.direction != direction;
}

class _GlassMenu<T> extends StatelessWidget {
  const _GlassMenu({required this.entries});

  final List<GlassMenuEntry<T>> entries;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in entries)
            switch (e) {
              GlassMenuDivider<T>() => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                child: Divider(height: 1, color: t.hairline),
              ),
              GlassMenuLabel<T>(:final text) => Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.textTertiary,
                  ),
                ),
              ),
              GlassMenuItem<T>() => _MenuRow<T>(item: e),
            },
        ],
      ),
    );
  }
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({required this.item});

  final GlassMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      onTap: item.enabled ? () => Navigator.of(context).pop(item.value) : null,
      semanticLabel: item.label,
      selected: item.checked,
      radius: 10,
      builder: (context, s) {
        final color = !s.enabled
            ? t.textDisabled
            : item.danger
            ? t.danger
            : t.text;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: s.hovered
                ? (item.danger ? t.dangerSubtle : t.glassHover)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 17,
                  color: item.danger || !s.enabled ? color : t.textSecondary,
                ),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: item.checked
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              if (item.checked)
                Icon(ClassroomIcons.check, size: 16, color: t.accentText),
            ],
          ),
        );
      },
    );
  }
}
