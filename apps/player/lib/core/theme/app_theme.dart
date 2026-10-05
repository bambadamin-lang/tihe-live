import 'package:flutter/material.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

import 'app_colors.dart';
import 'tokens.dart';

/// The app's visual system: the classroom's glass theme, in light and dark, everywhere.
///
/// Dark-first because the product is a video player: a bright chrome around a lecture is fatiguing,
/// and most watching happens in the evening. Light is a full equal, for students who study by day.
///
/// Components read [AppColors] (the player's roles) or [ClassroomTheme] (the glass), and both come
/// from one palette. Pages are transparent: the app paints the glass backdrop once, behind every
/// route (see main.dart), and surfaces are translucent glass over it.
class AppTheme {
  const AppTheme._();

  /// Modam, the institute's typeface, registered at start-up from the classroom package
  /// (ClassroomFonts), so the app and its classes share one family. Vazirmatn, bundled with the
  /// app, covers anything Modam lacks ("…", "·", "²").
  static const fontFamily = 'Modam';
  static const fontFallback = ['Vazirmatn', 'Noto Sans Arabic', 'Tahoma'];

  static ThemeData dark() => _build(AppColors.dark, ClassroomTheme.forBrightness(Brightness.dark));

  static ThemeData light() =>
      _build(AppColors.light, ClassroomTheme.forBrightness(Brightness.light));

  static ThemeData of(Brightness brightness) => brightness == Brightness.dark ? dark() : light();

  /// The type scale.
  ///
  /// Persian script has taller ascenders and descenders than Latin, so line heights run higher than
  /// a Latin UI would use; tighter values clip diacritics. Letter spacing stays at zero everywhere:
  /// tracking breaks the joins of a cursive script. Hierarchy comes from size and a restrained
  /// weight step (400 → 500 → 600), never from bold body text.
  static TextTheme textTheme(AppColors c) => TextTheme(
    // Page titles.
    headlineSmall: TextStyle(fontSize: 24, height: 1.4, fontWeight: FontWeight.w600, color: c.text),
    // Compact page titles, dialog titles.
    titleLarge: TextStyle(fontSize: 19, height: 1.45, fontWeight: FontWeight.w600, color: c.text),
    // Section titles.
    titleMedium: TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w600, color: c.text),
    // Item titles in lists and cards.
    titleSmall: TextStyle(fontSize: 14, height: 1.55, fontWeight: FontWeight.w500, color: c.text),
    bodyLarge: TextStyle(fontSize: 15, height: 1.75, color: c.text),
    bodyMedium: TextStyle(fontSize: 14, height: 1.7, color: c.text),
    // Secondary text and metadata.
    bodySmall: TextStyle(fontSize: 12.5, height: 1.6, color: c.textSecondary),
    // Buttons.
    labelLarge: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w500, color: c.text),
    // Field labels, tabs, nav items.
    labelMedium: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w500, color: c.text),
    // Badges, overlines, timestamps.
    labelSmall: TextStyle(
      fontSize: 11.5,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: c.textSecondary,
    ),
  );

  static ThemeData _build(AppColors c, ClassroomTheme glass) {
    final brightness = glass.brightness;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSubtle,
      onPrimaryContainer: c.accentText,
      secondary: c.textSecondary,
      onSecondary: c.background,
      error: c.danger,
      onError: Colors.white,
      errorContainer: c.dangerSubtle,
      onErrorContainer: c.danger,
      surface: c.background,
      onSurface: c.text,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceHover,
      outline: c.borderStrong,
      outlineVariant: c.border,
      inverseSurface: c.inverse,
      onInverseSurface: c.onInverse,
      scrim: c.scrim,
      shadow: c.shadow,
      surfaceTint: Colors.transparent,
    );
    final text = textTheme(c);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: color, width: width),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      textTheme: text,
      // Both extensions: the player's roles and the classroom's glass, which the classroom pages
      // and the Glass widgets read.
      extensions: [c, glass],
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: glass.glassStrong,
      dividerColor: c.border,
      hoverColor: c.surfaceHover,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SubtlePageTransition(),
          TargetPlatform.iOS: _SubtlePageTransition(),
          TargetPlatform.windows: _SubtlePageTransition(),
          TargetPlatform.macOS: _SubtlePageTransition(),
          TargetPlatform.linux: _SubtlePageTransition(),
        },
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.3),
        selectionHandleColor: c.accent,
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.textSecondary, size: 18),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hoverColor: Colors.transparent,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.x3, vertical: 11),
        hintStyle: text.bodyMedium?.copyWith(color: c.textTertiary),
        labelStyle: text.labelMedium?.copyWith(color: c.textSecondary),
        prefixIconColor: c.textTertiary,
        suffixIconColor: c.textTertiary,
        border: inputBorder(c.border),
        enabledBorder: inputBorder(c.border),
        focusedBorder: inputBorder(c.accent),
        errorBorder: inputBorder(c.danger),
        focusedErrorBorder: inputBorder(c.danger),
        disabledBorder: inputBorder(c.border),
        errorStyle: text.bodySmall?.copyWith(color: c.danger),
      ),
      // Stock buttons map onto the same variants as AppButton, for anything Material builds itself
      // (date pickers, licence page).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(0, 36),
          side: BorderSide(color: c.border),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          iconSize: 18,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceHover,
        circularTrackColor: Colors.transparent,
        refreshBackgroundColor: c.surface,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: text.labelSmall?.copyWith(color: c.onInverse),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2, vertical: AppSpace.x1 + 1),
        decoration: BoxDecoration(color: c.inverse, borderRadius: AppRadius.smAll),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.inverse,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.onInverse),
        actionTextColor: c.onInverse,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: glass.glassStrong,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: c.border),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: glass.glassStrong,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        showDragHandle: true,
        dragHandleColor: c.borderStrong,
        dragHandleSize: const Size(36, 4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: glass.glassStrong,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: c.shadow,
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: c.border),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(AppRadius.full),
        thumbColor: WidgetStatePropertyAll(c.borderStrong),
        crossAxisMargin: 2,
      ),
    );
  }
}

/// A short fade with a few pixels of travel.
///
/// Replaces the platform defaults (Android's zoom, iOS's full-width slide), which are heavy for a
/// tool people move around in quickly, and inconsistent between the two platforms this app ships on.
class _SubtlePageTransition extends PageTransitionsBuilder {
  const _SubtlePageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    // Pages are transparent over the shared glass backdrop, so the outgoing page fades out too;
    // otherwise both would show through each other for the length of the transition.
    final leaving = CurvedAnimation(parent: secondaryAnimation, curve: AppMotion.curve);
    return FadeTransition(
      opacity: ReverseAnimation(leaving),
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
