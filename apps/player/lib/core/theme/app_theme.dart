import 'package:flutter/material.dart';

/// The app's visual system.
///
/// Built around a dark-first palette because the product is a video player: a bright chrome around
/// a lecture is fatiguing, and most watching happens in the evening.
class AppTheme {
  const AppTheme._();

  static const _seed = Color(0xFF2D6A9F);

  /// Vazirmatn throughout. It carries Latin glyphs as well as Persian, so a mixed course title
  /// ("Calculus — مشتق") does not change face mid-line, which is the usual giveaway of a Persian UI
  /// built on a Latin font.
  static const fontFamily = 'Vazirmatn';

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF101418),
      cardTheme: _cardTheme(const Color(0xFF181D23)),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: _seed);
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      cardTheme: _cardTheme(Colors.white),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      // Persian script has taller ascenders and descenders than Latin; the default line heights
      // clip diacritics and leave compound words looking cramped.
      textTheme: const TextTheme(
        displayLarge: TextStyle(height: 1.4),
        headlineMedium: TextStyle(height: 1.4, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(height: 1.5, fontWeight: FontWeight.w500),
        titleMedium: TextStyle(height: 1.5, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(height: 1.7),
        bodyMedium: TextStyle(height: 1.7),
        bodySmall: TextStyle(height: 1.6),
        labelLarge: TextStyle(height: 1.4, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w500),
        ),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    );
  }

  static CardThemeData _cardTheme(Color color) => CardThemeData(
        color: color,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
}
