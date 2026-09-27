import 'package:flutter/material.dart';

/// Semantic colour tokens.
///
/// Components read roles ("the border", "secondary text"), never raw hex values, so the palette can
/// change in one place. The palette is deliberately narrow: neutrals carry the interface, and the
/// single accent is reserved for what is interactive, selected, focused or in progress.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.surfacePressed,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.onAccent,
    required this.accentSubtle,
    required this.accentText,
    required this.success,
    required this.successSubtle,
    required this.warning,
    required this.warningSubtle,
    required this.danger,
    required this.dangerHover,
    required this.dangerSubtle,
    required this.inverse,
    required this.onInverse,
    required this.scrim,
    required this.shadow,
  });

  /// The app canvas.
  final Color background;

  /// Navigation chrome, one step off the canvas so content reads as the foreground.
  final Color sidebar;

  /// Inputs, grouped lists, dialogs.
  final Color surface;

  /// Controls resting on a surface: secondary buttons, segmented tracks, icon tiles.
  final Color surfaceRaised;
  final Color surfaceHover;
  final Color surfacePressed;

  /// Hairlines. One pixel, low contrast: separation without weight.
  final Color border;
  final Color borderStrong;

  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color onAccent;

  /// Selected rows and accent badges.
  final Color accentSubtle;

  /// Accent used as text or icon colour on the canvas; tuned for contrast in each brightness.
  final Color accentText;

  final Color success;
  final Color successSubtle;
  final Color warning;
  final Color warningSubtle;
  final Color danger;
  final Color dangerHover;
  final Color dangerSubtle;

  /// Tooltips and toasts: the opposite of the canvas, so they read above everything.
  final Color inverse;
  final Color onInverse;

  final Color scrim;
  final Color shadow;

  static const dark = AppColors(
    background: Color(0xFF0A0A0B),
    sidebar: Color(0xFF0F0F11),
    surface: Color(0xFF121214),
    surfaceRaised: Color(0xFF19191C),
    surfaceHover: Color(0xFF1E1E22),
    surfacePressed: Color(0xFF26262B),
    border: Color(0xFF232327),
    borderStrong: Color(0xFF32323A),
    text: Color(0xFFEDEDEF),
    textSecondary: Color(0xFFA0A0AB),
    textTertiary: Color(0xFF70707B),
    textDisabled: Color(0xFF4E4E57),
    accent: Color(0xFF3D7BFA),
    accentHover: Color(0xFF5289FB),
    accentPressed: Color(0xFF2F6AE6),
    onAccent: Color(0xFFFFFFFF),
    accentSubtle: Color(0x243D7BFA),
    accentText: Color(0xFF7AA5FF),
    success: Color(0xFF3DB57F),
    successSubtle: Color(0x1F3DB57F),
    warning: Color(0xFFE2A336),
    warningSubtle: Color(0x1FE2A336),
    danger: Color(0xFFEB5757),
    dangerHover: Color(0xFFF06B6B),
    dangerSubtle: Color(0x1FEB5757),
    inverse: Color(0xFFEDEDEF),
    onInverse: Color(0xFF111113),
    scrim: Color(0xB3000000),
    shadow: Color(0x66000000),
  );

  static const light = AppColors(
    background: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF8F8F9),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF4F4F5),
    surfaceHover: Color(0xFFF0F0F2),
    surfacePressed: Color(0xFFE7E7EA),
    border: Color(0xFFE6E6E9),
    borderStrong: Color(0xFFD4D4D8),
    text: Color(0xFF18181B),
    textSecondary: Color(0xFF55555E),
    textTertiary: Color(0xFF7D7D87),
    textDisabled: Color(0xFFB4B4BC),
    accent: Color(0xFF2563EB),
    accentHover: Color(0xFF1D56D8),
    accentPressed: Color(0xFF1A4CC0),
    onAccent: Color(0xFFFFFFFF),
    accentSubtle: Color(0x172563EB),
    accentText: Color(0xFF1F57D6),
    success: Color(0xFF16915A),
    successSubtle: Color(0x1A16915A),
    warning: Color(0xFFB7791F),
    warningSubtle: Color(0x1FB7791F),
    danger: Color(0xFFD93636),
    dangerHover: Color(0xFFC22D2D),
    dangerSubtle: Color(0x14D93636),
    inverse: Color(0xFF18181B),
    onInverse: Color(0xFFFAFAFA),
    scrim: Color(0x66000000),
    shadow: Color(0x1F000000),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      sidebar: l(sidebar, other.sidebar),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      surfacePressed: l(surfacePressed, other.surfacePressed),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      text: l(text, other.text),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      textDisabled: l(textDisabled, other.textDisabled),
      accent: l(accent, other.accent),
      accentHover: l(accentHover, other.accentHover),
      accentPressed: l(accentPressed, other.accentPressed),
      onAccent: l(onAccent, other.onAccent),
      accentSubtle: l(accentSubtle, other.accentSubtle),
      accentText: l(accentText, other.accentText),
      success: l(success, other.success),
      successSubtle: l(successSubtle, other.successSubtle),
      warning: l(warning, other.warning),
      warningSubtle: l(warningSubtle, other.warningSubtle),
      danger: l(danger, other.danger),
      dangerHover: l(dangerHover, other.dangerHover),
      dangerSubtle: l(dangerSubtle, other.dangerSubtle),
      inverse: l(inverse, other.inverse),
      onInverse: l(onInverse, other.onInverse),
      scrim: l(scrim, other.scrim),
      shadow: l(shadow, other.shadow),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}
