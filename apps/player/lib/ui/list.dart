import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_icons.dart';
import '../core/theme/tokens.dart';
import 'buttons.dart';
import 'pressable.dart';
import 'primitives.dart';

/// A row: leading mark, title, optional subtitle, trailing slot.
///
/// The one row used across the app — courses, sessions, devices, settings — so every list has the
/// same height, padding and hover. A disabled row keeps its content legible but dimmed, so a student
/// can see what exists even when they cannot open it yet.
class AppListRow extends StatelessWidget {
  const AppListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.showChevron = false,
    this.destructive = false,
    this.dense = false,
    this.padding,
    this.titleMaxLines = 1,
    this.semanticLabel,
    super.key,
  });

  final String title;

  /// A string, or any widget (a meta line with a progress bar, a lock reason).
  final Object? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final bool showChevron;
  final bool destructive;
  final bool dense;
  final EdgeInsetsGeometry? padding;
  final int titleMaxLines;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final touch = isTouchPlatform(context);

    final titleColor = !enabled
        ? colors.textTertiary
        : destructive
            ? colors.danger
            : colors.text;

    final subtitleWidget = switch (subtitle) {
      final String text => Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: enabled ? colors.textSecondary : colors.textDisabled,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      final Widget widget => widget,
      _ => null,
    };

    final minHeight = dense ? (touch ? 48.0 : 40.0) : (touch ? 60.0 : 52.0);

    return Pressable(
      onTap: enabled ? onTap : null,
      semanticLabel: semanticLabel ?? title,
      color: selected ? colors.accentSubtle : Colors.transparent,
      hoverColor: selected ? colors.accentSubtle : null,
      builder: (context, state) => ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: padding ??
              EdgeInsets.symmetric(
                horizontal: AppSpace.x3,
                vertical: dense ? AppSpace.x2 : AppSpace.x2 + 2,
              ),
          child: Row(
            children: [
              if (leading != null) ...[
                Opacity(opacity: enabled ? 1 : 0.55, child: leading),
                const SizedBox(width: AppSpace.x3),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: titleColor,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      maxLines: titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleWidget != null) ...[
                      const SizedBox(height: 2),
                      subtitleWidget,
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpace.x3),
                trailing!,
              ],
              if (showChevron && enabled) ...[
                const SizedBox(width: AppSpace.x2),
                AnimatedSlide(
                  duration: AppMotion.fast,
                  offset: Offset(state.hovered ? -0.12 : 0, 0) *
                      (Directionality.of(context) == TextDirection.rtl ? 1 : -1),
                  child: Icon(
                    AppIcons.forward,
                    size: 16,
                    color: state.hovered ? colors.textSecondary : colors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rows that belong together, in one bordered group with hairlines between them.
///
/// For settings-style lists only. Content lists (courses, sessions) are flat, without a container.
class AppListGroup extends StatelessWidget {
  const AppListGroup({required this.children, this.dividerIndent = 0, super.key});

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Hairline(indent: dividerIndent),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
