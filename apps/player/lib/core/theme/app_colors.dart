import 'package:flutter/material.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

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

  /// The palette is the classroom's glass theme (packages/tihe_classroom), so the library, the
  /// dashboard and the live class are one app to look at. Surfaces are translucent glass over the
  /// backdrop the app paints behind every screen; there is one palette to change, in
  /// [ClassroomTheme].
  factory AppColors.fromClassroom(ClassroomTheme t) => AppColors(
    background: t.canvas,
    sidebar: t.glass,
    surface: t.glass,
    surfaceRaised: t.glassHover,
    surfaceHover: t.glassHover,
    surfacePressed: t.glassPressed,
    border: t.hairline,
    borderStrong: t.edgeLow,
    text: t.text,
    textSecondary: t.textSecondary,
    textTertiary: t.textTertiary,
    textDisabled: t.textDisabled,
    accent: t.accent,
    accentHover: t.accentHover,
    accentPressed: t.accentHover,
    onAccent: t.onAccent,
    accentSubtle: t.accentSubtle,
    accentText: t.accentText,
    success: t.success,
    successSubtle: t.successSubtle,
    warning: t.warning,
    warningSubtle: t.warningSubtle,
    danger: t.danger,
    dangerHover: t.dangerHover,
    dangerSubtle: t.dangerSubtle,
    inverse: t.inverse,
    onInverse: t.onInverse,
    scrim: t.scrim,
    shadow: t.shadow,
  );

  static final dark = AppColors.fromClassroom(ClassroomTheme.dark);
  static final light = AppColors.fromClassroom(ClassroomTheme.light);

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
