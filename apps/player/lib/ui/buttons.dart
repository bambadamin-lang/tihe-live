import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/tokens.dart';
import 'pressable.dart';
import 'progress.dart';

enum AppButtonVariant {
  /// The one main action on a screen.
  primary,

  /// Everything else that deserves a visible button.
  secondary,

  /// Low-emphasis actions inside content: "show more", "resend code".
  ghost,

  /// Confirms something irreversible.
  danger,

  /// An irreversible action offered, not yet confirmed: "sign out", "remove".
  dangerGhost,
}

enum AppButtonSize { small, medium, large }

/// Whether the platform is primarily touch, where targets need to be taller.
bool isTouchPlatform(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

/// The app's button.
///
/// Loading replaces the label with a spinner *inside the same box*, so the button does not change
/// width and the layout does not jump while a request is in flight. A loading button ignores taps.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = AppButtonVariant.secondary,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
    this.autofocus = false,
    super.key,
  });

  const AppButton.primary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
    this.autofocus = false,
    super.key,
  }) : variant = AppButtonVariant.primary;

  const AppButton.ghost({
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
    this.autofocus = false,
    super.key,
  }) : variant = AppButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool expand;
  final String? tooltip;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final touch = isTouchPlatform(context);
    final enabled = onPressed != null && !loading;

    final (height, padding, fontSize, iconSize) = switch (size) {
      AppButtonSize.small => (touch ? 34.0 : 30.0, AppSpace.x3 - 2, 13.0, 14.0),
      AppButtonSize.medium => (touch ? 40.0 : 36.0, AppSpace.x4 - 2, 14.0, 16.0),
      AppButtonSize.large => (touch ? 48.0 : 44.0, AppSpace.x5, 14.5, 18.0),
    };

    final (Color bg, Color hover, Color pressed, Color fg, BoxBorder? border) = switch (variant) {
      AppButtonVariant.primary => (
          colors.accent,
          colors.accentHover,
          colors.accentPressed,
          colors.onAccent,
          null,
        ),
      AppButtonVariant.secondary => (
          colors.surfaceRaised,
          colors.surfaceHover,
          colors.surfacePressed,
          colors.text,
          Border.all(color: colors.border),
        ),
      AppButtonVariant.ghost => (
          Colors.transparent,
          colors.surfaceHover,
          colors.surfacePressed,
          colors.text,
          null,
        ),
      AppButtonVariant.danger => (
          colors.danger,
          colors.dangerHover,
          colors.danger,
          Colors.white,
          null,
        ),
      AppButtonVariant.dangerGhost => (
          Colors.transparent,
          colors.dangerSubtle,
          colors.dangerSubtle,
          colors.danger,
          null,
        ),
    };

    // Disabled keeps the shape but drops the colour, so the button stays findable.
    final solid = variant == AppButtonVariant.primary || variant == AppButtonVariant.danger;
    final restingBg = onPressed == null && solid ? colors.surfaceRaised : bg;
    final foreground = onPressed == null ? colors.textDisabled : fg;

    final textStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: foreground,
    );

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: foreground),
          const SizedBox(width: AppSpace.x2),
        ],
        Flexible(
          child: Text(label, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: AppSpace.x2 - 2),
          Icon(trailingIcon, size: iconSize, color: foreground),
        ],
      ],
    );

    return Pressable(
      onTap: enabled ? onPressed : null,
      autofocus: autofocus,
      tooltip: tooltip,
      semanticLabel: label,
      color: restingBg,
      hoverColor: hover,
      pressedColor: pressed,
      border: border,
      mouseCursor: loading ? SystemMouseCursors.progress : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The label stays laid out while loading, invisible, so the width holds.
              Opacity(opacity: loading ? 0 : 1, child: content),
              if (loading) AppSpinner(size: iconSize, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

enum AppIconButtonVariant { ghost, secondary }

/// A square icon-only button. Always has a tooltip, because an icon alone is not a label.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.variant = AppIconButtonVariant.ghost,
    this.size = AppButtonSize.medium,
    this.selected = false,
    this.loading = false,
    this.color,
    this.hoverColor,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;
  final AppButtonSize size;
  final bool selected;
  final bool loading;

  /// Overrides the resting icon colour, e.g. for a destructive action.
  final Color? color;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final touch = isTouchPlatform(context);

    final (extent, iconSize) = switch (size) {
      AppButtonSize.small => (touch ? 36.0 : 28.0, 15.0),
      AppButtonSize.medium => (touch ? 40.0 : 32.0, 17.0),
      AppButtonSize.large => (touch ? 48.0 : 40.0, 20.0),
    };

    final enabled = onPressed != null && !loading;
    final fg = !enabled && !loading
        ? colors.textDisabled
        : selected
            ? colors.accentText
            : (color ?? colors.textSecondary);

    return Pressable(
      onTap: enabled ? onPressed : null,
      tooltip: tooltip,
      semanticLabel: tooltip,
      color: selected
          ? colors.accentSubtle
          : variant == AppIconButtonVariant.secondary
              ? colors.surfaceRaised
              : Colors.transparent,
      hoverColor: hoverColor,
      border: variant == AppIconButtonVariant.secondary ? Border.all(color: colors.border) : null,
      builder: (context, state) => SizedBox.square(
        dimension: extent,
        child: Center(
          child: loading
              ? AppSpinner(size: iconSize - 2)
              : Icon(
                  icon,
                  size: iconSize,
                  color: state.hovered && color == null && !selected ? colors.text : fg,
                ),
        ),
      ),
    );
  }
}
