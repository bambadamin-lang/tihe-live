import 'package:flutter/material.dart';

/// The classroom's look (docs/11 §11): frosted glass over a softly lit canvas, in a light and
/// a dark variant.
///
/// Glass because a classroom is layers — pods over the stage, bars and sheets over pods — and
/// translucency keeps each layer's place in the stack readable without heavy borders or
/// shadows. The canvas behind it is only a few soft glows, so the blur has something to refract
/// but nothing competes with the class itself.
///
/// The neutrals, accent and status colours match the video player's design system, so the two
/// apps read as one product. Every colour and depth the classroom widgets use comes from here,
/// through a [ThemeExtension].
@immutable
class ClassroomTheme extends ThemeExtension<ClassroomTheme> {
  const ClassroomTheme({
    required this.brightness,
    required this.canvas,
    required this.glows,
    required this.glass,
    required this.glassStrong,
    required this.glassHover,
    required this.glassPressed,
    required this.edgeHigh,
    required this.edgeLow,
    required this.hairline,
    required this.shadow,
    required this.screen,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.accentHover,
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
    required this.roleHost,
    required this.roleCohost,
    required this.rolePresenter,
    required this.inverse,
    required this.onInverse,
    required this.scrim,
    this.fontFamily = 'Peyda',
    this.fontFallback = const [
      'Vazirmatn',
      'Noto Sans Arabic',
      'Tahoma',
      'sans-serif',
    ],
  });

  final Brightness brightness;

  /// The base colour under the glows.
  final Color canvas;

  /// Three soft light sources: top start, bottom end, bottom centre.
  final List<Color> glows;

  /// Pods, bars, chips.
  final Color glass;

  /// Sheets and menus, which sit over busier content and need more body.
  final Color glassStrong;
  final Color glassHover;
  final Color glassPressed;

  /// The lit top edge and the shaded bottom edge of a glass rim.
  final Color edgeHigh;
  final Color edgeLow;

  /// Separators inside glass.
  final Color hairline;
  final Color shadow;

  /// Behind video and screen share. Dark in both themes: video is.
  final Color screen;

  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  final Color accent;
  final Color accentHover;
  final Color onAccent;
  final Color accentSubtle;
  final Color accentText;

  final Color success;
  final Color successSubtle;
  final Color warning;
  final Color warningSubtle;
  final Color danger;
  final Color dangerHover;
  final Color dangerSubtle;

  final Color roleHost;
  final Color roleCohost;
  final Color rolePresenter;

  /// Tooltips and toasts.
  final Color inverse;
  final Color onInverse;
  final Color scrim;

  final String fontFamily;
  final List<String> fontFallback;

  bool get isDark => brightness == Brightness.dark;

  /// Blur behind glass, in logical pixels of sigma.
  double get blur => 24;

  static const dark = ClassroomTheme(
    brightness: Brightness.dark,
    canvas: Color(0xFF07080B),
    glows: [Color(0x473D7BFA), Color(0x387C5CFA), Color(0x2422B8A6)],
    glass: Color(0x0FFFFFFF),
    glassStrong: Color(0xB8141519),
    glassHover: Color(0x1AFFFFFF),
    glassPressed: Color(0x24FFFFFF),
    edgeHigh: Color(0x2EFFFFFF),
    edgeLow: Color(0x0AFFFFFF),
    hairline: Color(0x14FFFFFF),
    shadow: Color(0x59000000),
    screen: Color(0xFF0B0C10),
    text: Color(0xFFF2F3F5),
    textSecondary: Color(0xFFA3A7B3),
    textTertiary: Color(0xFF6E7380),
    textDisabled: Color(0xFF4B4F59),
    // Deep enough that white labels on it pass WCAG AA (4.6:1); checked with
    // replica/design/tokens.dark.json.
    accent: Color(0xFF266BF9),
    accentHover: Color(0xFF1F5FE6),
    onAccent: Color(0xFFFFFFFF),
    accentSubtle: Color(0x2E266BF9),
    accentText: Color(0xFF8AB0FF),
    success: Color(0xFF3DB57F),
    successSubtle: Color(0x293DB57F),
    warning: Color(0xFFE2A336),
    warningSubtle: Color(0x2EE2A336),
    danger: Color(0xFFEE7272),
    dangerHover: Color(0xFFF28A8A),
    dangerSubtle: Color(0x33EE7272),
    roleHost: Color(0xFFB39DFF),
    roleCohost: Color(0xFF8AB0FF),
    rolePresenter: Color(0xFF5FD4C0),
    inverse: Color(0xFFF2F3F5),
    onInverse: Color(0xFF111217),
    scrim: Color(0x99000000),
  );

  static const light = ClassroomTheme(
    brightness: Brightness.light,
    canvas: Color(0xFFEEF1F7),
    glows: [Color(0x4D3D7BFA), Color(0x3D8B6CFF), Color(0x33FF9E7A)],
    glass: Color(0x8CFFFFFF),
    glassStrong: Color(0xE0FBFCFE),
    glassHover: Color(0xB3FFFFFF),
    glassPressed: Color(0xCCF3F5FA),
    edgeHigh: Color(0xE6FFFFFF),
    edgeLow: Color(0x1A1B2440),
    hairline: Color(0x141B2440),
    shadow: Color(0x1F1B2440),
    screen: Color(0xFF12141A),
    text: Color(0xFF14161C),
    textSecondary: Color(0xFF555B69),
    textTertiary: Color(0xFF858B98),
    textDisabled: Color(0xFFB2B6C0),
    accent: Color(0xFF2563EB),
    accentHover: Color(0xFF1D56D8),
    onAccent: Color(0xFFFFFFFF),
    accentSubtle: Color(0x1F2563EB),
    accentText: Color(0xFF1F57D6),
    // Error and success text pass AA on glass and on their own tinted boxes
    // (replica/design/tokens.light.json).
    success: Color(0xFF148150),
    successSubtle: Color(0x22148150),
    warning: Color(0xFFB7791F),
    warningSubtle: Color(0x26D99A2B),
    danger: Color(0xFFC12424),
    dangerHover: Color(0xFFA81F1F),
    dangerSubtle: Color(0x1FC12424),
    roleHost: Color(0xFF6D4AE0),
    roleCohost: Color(0xFF1F57D6),
    rolePresenter: Color(0xFF0E8A78),
    inverse: Color(0xFF14161C),
    onInverse: Color(0xFFF7F8FA),
    scrim: Color(0x4D14161C),
  );

  static ClassroomTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static ClassroomTheme of(BuildContext context) =>
      Theme.of(context).extension<ClassroomTheme>() ?? dark;

  /// A floating layer: one wide, soft shadow. Glass needs little — the rim does the work.
  List<BoxShadow> get floating => [
    BoxShadow(color: shadow, blurRadius: 32, offset: const Offset(0, 12)),
  ];

  /// Something small that sits on glass: a chip, a badge.
  List<BoxShadow> get lifted => [
    BoxShadow(
      color: shadow.withValues(alpha: shadow.a * 0.6),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  /// The rim of a glass surface: lit along the top, fading towards the bottom.
  Gradient get rim => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [edgeHigh, edgeLow],
  );

  @override
  ClassroomTheme copyWith({String? fontFamily}) => ClassroomTheme(
    brightness: brightness,
    canvas: canvas,
    glows: glows,
    glass: glass,
    glassStrong: glassStrong,
    glassHover: glassHover,
    glassPressed: glassPressed,
    edgeHigh: edgeHigh,
    edgeLow: edgeLow,
    hairline: hairline,
    shadow: shadow,
    screen: screen,
    text: text,
    textSecondary: textSecondary,
    textTertiary: textTertiary,
    textDisabled: textDisabled,
    accent: accent,
    accentHover: accentHover,
    onAccent: onAccent,
    accentSubtle: accentSubtle,
    accentText: accentText,
    success: success,
    successSubtle: successSubtle,
    warning: warning,
    warningSubtle: warningSubtle,
    danger: danger,
    dangerHover: dangerHover,
    dangerSubtle: dangerSubtle,
    roleHost: roleHost,
    roleCohost: roleCohost,
    rolePresenter: rolePresenter,
    inverse: inverse,
    onInverse: onInverse,
    scrim: scrim,
    fontFamily: fontFamily ?? this.fontFamily,
    fontFallback: fontFallback,
  );

  // Switching theme mid-class is a cut, not a cross-fade: the glass blur would have to be
  // recomputed every frame of a lerp for no benefit.
  @override
  ClassroomTheme lerp(ClassroomTheme? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// The ThemeData the classroom runs under: Persian type, RTL-friendly components, and the
/// [ClassroomTheme] extension. Material widgets inside the classroom (switches, menus, text
/// fields) are themed onto the same tokens, so they sit on the glass without looking borrowed.
ThemeData buildClassroomThemeData([ClassroomTheme t = ClassroomTheme.dark]) {
  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.accentSubtle,
    onPrimaryContainer: t.accentText,
    secondary: t.textSecondary,
    onSecondary: t.canvas,
    error: t.danger,
    onError: Colors.white,
    errorContainer: t.dangerSubtle,
    onErrorContainer: t.danger,
    surface: t.canvas,
    onSurface: t.text,
    onSurfaceVariant: t.textSecondary,
    surfaceContainerHighest: t.glassHover,
    outline: t.edgeLow,
    outlineVariant: t.hairline,
    inverseSurface: t.inverse,
    onInverseSurface: t.onInverse,
    shadow: t.shadow,
    scrim: t.scrim,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    fontFamily: t.fontFamily,
    fontFamilyFallback: t.fontFallback,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
  final radius = BorderRadius.circular(10);
  final labelStyle = TextStyle(
    fontFamily: t.fontFamily,
    fontFamilyFallback: t.fontFallback,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );
  return base.copyWith(
    extensions: [t],
    scaffoldBackgroundColor: t.canvas,
    textTheme: base.textTheme.apply(bodyColor: t.text, displayColor: t.text),
    iconTheme: IconThemeData(color: t.textSecondary, size: 18),
    dividerTheme: DividerThemeData(color: t.hairline, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: t.inverse,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: t.onInverse,
        fontFamily: t.fontFamily,
        fontFamilyFallback: t.fontFallback,
        fontSize: 12.5,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.isDark ? const Color(0xF21A1B20) : const Color(0xF7FFFFFF),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: t.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.hairline),
      ),
      textStyle: TextStyle(
        color: t.text,
        fontFamily: t.fontFamily,
        fontFamilyFallback: t.fontFallback,
        fontSize: 14,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        disabledBackgroundColor: t.glassHover,
        disabledForegroundColor: t.textDisabled,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: labelStyle,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        backgroundColor: t.glass,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: BorderSide(color: t.edgeLow),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: labelStyle.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accentText,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: labelStyle.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.textSecondary,
        hoverColor: t.glassHover,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.onAccent : t.textTertiary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.glassHover,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.edgeLow,
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: t.text,
      iconColor: t.textSecondary,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.glass,
      isDense: true,
      hintStyle: TextStyle(color: t.textTertiary),
      labelStyle: TextStyle(color: t.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: t.edgeLow),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: t.edgeLow),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: t.accent, width: 1.5),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.accent.withValues(alpha: 0.3),
      selectionHandleColor: t.accent,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: t.glass,
        foregroundColor: t.textSecondary,
        selectedBackgroundColor: t.accentSubtle,
        selectedForegroundColor: t.accentText,
        side: BorderSide(color: t.edgeLow),
        textStyle: labelStyle.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          t.isDark ? const Color(0xF21A1B20) : const Color(0xF7FFFFFF),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.inverse,
      contentTextStyle: TextStyle(color: t.onInverse),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
