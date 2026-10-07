import 'package:flutter/material.dart';

import 'cursor.dart';
import 'fonts.dart';

/// The classroom's look (docs/11 §11): frosted navy glass floating in a night sky, with two
/// lit planets at the edges and faint orbits between them — and a daylight variant of the same.
///
/// Glass because a classroom is layers — pods over the stage, bars and sheets over pods — and
/// translucency keeps each layer's place in the stack readable without heavy borders or
/// shadows. The sky behind it is painted once: the planets give the blur something to refract,
/// and they sit at the edges, where the class never is.
///
/// The accent is one electric blue, used as a gradient on the few things that start something
/// (join, send) and flat everywhere else. Every colour and depth the classroom widgets use
/// comes from here, through a [ThemeExtension].
@immutable
class ClassroomTheme extends ThemeExtension<ClassroomTheme> {
  const ClassroomTheme({
    required this.brightness,
    required this.canvas,
    required this.canvasTop,
    required this.glows,
    required this.planet,
    required this.orbit,
    required this.glass,
    required this.glassStrong,
    required this.glassHover,
    required this.glassPressed,
    required this.edgeHigh,
    required this.edgeLow,
    required this.hairline,
    required this.shadow,
    required this.screen,
    required this.field,
    required this.fieldBorder,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.accentEnd,
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
    this.fontFamily = 'Modam',
    this.fontFallback = const [
      'Vazirmatn',
      'Noto Sans Arabic',
      'Tahoma',
      'sans-serif',
    ],
  });

  final Brightness brightness;

  /// The sky: [canvasTop] along the top edge, fading into [canvas].
  final Color canvas;
  final Color canvasTop;

  /// Three soft light sources: top centre, bottom start, bottom end.
  final List<Color> glows;

  /// A planet from its night side to its lit rim: shade, body, lit face, rim.
  final List<Color> planet;

  /// The faint orbit lines across the sky.
  final Color orbit;

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

  /// Text fields, pickers and list rows sunk into a glass card.
  final Color field;
  final Color fieldBorder;

  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  /// The accent, and where its gradient ends.
  final Color accent;
  final Color accentEnd;
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
    canvas: Color(0xFF060F22),
    canvasTop: Color(0xFF0B1B3A),
    glows: [Color(0x402F6FFE), Color(0x455B3CF0), Color(0x2E1F7BFF)],
    planet: [
      Color(0xFF070D2B),
      Color(0xFF12246E),
      Color(0xFF2B4FE0),
      Color(0xFF7C9CFF),
    ],
    orbit: Color(0x474F6FE8),
    glass: Color(0xA8101B34),
    glassStrong: Color(0xF00D1730),
    glassHover: Color(0x178AA8FF),
    glassPressed: Color(0x268AA8FF),
    edgeHigh: Color(0x5C7C9CFF),
    edgeLow: Color(0x1F7C9CFF),
    hairline: Color(0x1C8AA8FF),
    shadow: Color(0x8C01040F),
    screen: Color(0xFF0A1122),
    field: Color(0x0FA8BEFF),
    fieldBorder: Color(0x298AA8FF),
    text: Color(0xFFF4F7FF),
    textSecondary: Color(0xFFA9B4D0),
    textTertiary: Color(0xFF6F7B9E),
    textDisabled: Color(0xFF465073),
    accent: Color(0xFF2F6FFE),
    accentEnd: Color(0xFF4A5BFF),
    accentHover: Color(0xFF4C84FF),
    onAccent: Color(0xFFFFFFFF),
    accentSubtle: Color(0x332F6FFE),
    accentText: Color(0xFF8DB0FF),
    success: Color(0xFF22DD95),
    successSubtle: Color(0x2922DD95),
    warning: Color(0xFFF5C451),
    warningSubtle: Color(0x2EF5C451),
    danger: Color(0xFFF0495E),
    dangerHover: Color(0xFFF5647A),
    dangerSubtle: Color(0x33F0495E),
    roleHost: Color(0xFF7FA6FF),
    roleCohost: Color(0xFFB39DFF),
    rolePresenter: Color(0xFF5FD4C0),
    inverse: Color(0xFFF4F7FF),
    onInverse: Color(0xFF0B1224),
    scrim: Color(0xA6030814),
  );

  static const light = ClassroomTheme(
    brightness: Brightness.light,
    canvas: Color(0xFFEAF0FB),
    canvasTop: Color(0xFFF6F9FF),
    glows: [Color(0x402F6FFE), Color(0x338B6CFF), Color(0x2638BDF8)],
    planet: [
      Color(0xFFDCE5FB),
      Color(0xFFB9CBF8),
      Color(0xFF7E9CF4),
      Color(0xFF4F74F0),
    ],
    orbit: Color(0x405C7BE0),
    glass: Color(0xB3FFFFFF),
    glassStrong: Color(0xF2FBFCFF),
    glassHover: Color(0x0F1E3A8A),
    glassPressed: Color(0x1A1E3A8A),
    edgeHigh: Color(0xF2FFFFFF),
    edgeLow: Color(0x241E3A8A),
    hairline: Color(0x171E3A8A),
    shadow: Color(0x241E3A8A),
    screen: Color(0xFF111A2E),
    field: Color(0x99F4F7FD),
    fieldBorder: Color(0x2E1E3A8A),
    text: Color(0xFF0F1830),
    textSecondary: Color(0xFF4D5A78),
    textTertiary: Color(0xFF8490AB),
    textDisabled: Color(0xFFB5BDD0),
    accent: Color(0xFF2563EB),
    accentEnd: Color(0xFF4F46E5),
    accentHover: Color(0xFF1D56D8),
    onAccent: Color(0xFFFFFFFF),
    accentSubtle: Color(0x1F2563EB),
    accentText: Color(0xFF1F57D6),
    success: Color(0xFF0FA36A),
    successSubtle: Color(0x220FA36A),
    warning: Color(0xFFC98A12),
    warningSubtle: Color(0x26E0A526),
    danger: Color(0xFFE0334A),
    dangerHover: Color(0xFFC92A40),
    dangerSubtle: Color(0x1FE0334A),
    roleHost: Color(0xFF1F57D6),
    roleCohost: Color(0xFF6D4AE0),
    rolePresenter: Color(0xFF0E8A78),
    inverse: Color(0xFF0F1830),
    onInverse: Color(0xFFF6F8FD),
    scrim: Color(0x4D0F1830),
  );

  /// [dark] or [light], set in [ClassroomFonts.family] (Modam unless the app chose another).
  static ClassroomTheme forBrightness(Brightness brightness) {
    final theme = brightness == Brightness.dark ? dark : light;
    return ClassroomFonts.family == theme.fontFamily
        ? theme
        : theme.copyWith(fontFamily: ClassroomFonts.family);
  }

  static ClassroomTheme of(BuildContext context) =>
      Theme.of(context).extension<ClassroomTheme>() ?? dark;

  /// A floating layer: one wide, soft shadow. Glass needs little — the rim does the work.
  List<BoxShadow> get floating => [
    BoxShadow(color: shadow, blurRadius: 36, offset: const Offset(0, 14)),
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

  /// The accent as light: across a primary button, from the reading start.
  Gradient accentGradient([TextDirection direction = TextDirection.rtl]) =>
      LinearGradient(
        begin: AlignmentDirectional.centerStart.resolve(direction),
        end: AlignmentDirectional.centerEnd.resolve(direction),
        colors: [accent, accentEnd],
      );

  /// The halo under something accent-filled.
  List<BoxShadow> accentGlow({double strength = 1}) => [
    BoxShadow(
      color: accent.withValues(alpha: (isDark ? 0.42 : 0.3) * strength),
      blurRadius: 22,
      offset: const Offset(0, 6),
    ),
  ];

  @override
  ClassroomTheme copyWith({String? fontFamily}) => ClassroomTheme(
    brightness: brightness,
    canvas: canvas,
    canvasTop: canvasTop,
    glows: glows,
    planet: planet,
    orbit: orbit,
    glass: glass,
    glassStrong: glassStrong,
    glassHover: glassHover,
    glassPressed: glassPressed,
    edgeHigh: edgeHigh,
    edgeLow: edgeLow,
    hairline: hairline,
    shadow: shadow,
    screen: screen,
    field: field,
    fieldBorder: fieldBorder,
    text: text,
    textSecondary: textSecondary,
    textTertiary: textTertiary,
    textDisabled: textDisabled,
    accent: accent,
    accentEnd: accentEnd,
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
/// fields) are themed onto the same tokens and the same cursor, so they sit on the glass without
/// looking borrowed.
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
    outline: t.fieldBorder,
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
  final radius = BorderRadius.circular(12);
  final labelStyle = TextStyle(
    fontFamily: t.fontFamily,
    fontFamilyFallback: t.fontFallback,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );
  const clickable = WidgetStatePropertyAll<MouseCursor?>(GlowCursors.click);
  final menuColor = t.isDark
      ? const Color(0xF50E1831)
      : const Color(0xF7FFFFFF);
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
        borderRadius: BorderRadius.circular(8),
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
      color: menuColor,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: t.shadow,
      mouseCursor: clickable,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.fieldBorder),
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
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: labelStyle,
        elevation: 0,
        enabledMouseCursor: GlowCursors.click,
        disabledMouseCursor: GlowCursors.basic,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        backgroundColor: t.field,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: BorderSide(color: t.fieldBorder),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: labelStyle.copyWith(fontWeight: FontWeight.w500),
        enabledMouseCursor: GlowCursors.click,
        disabledMouseCursor: GlowCursors.basic,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accentText,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: labelStyle.copyWith(fontWeight: FontWeight.w500),
        enabledMouseCursor: GlowCursors.click,
        disabledMouseCursor: GlowCursors.basic,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.textSecondary,
        hoverColor: t.glassHover,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        enabledMouseCursor: GlowCursors.click,
        disabledMouseCursor: GlowCursors.basic,
      ),
    ),
    switchTheme: SwitchThemeData(
      mouseCursor: clickable,
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.onAccent : t.textTertiary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.field,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.fieldBorder,
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: t.text,
      iconColor: t.textSecondary,
      mouseCursor: clickable,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.field,
      isDense: true,
      hintStyle: TextStyle(color: t.textTertiary),
      labelStyle: TextStyle(color: t.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: t.fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: t.fieldBorder),
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
        backgroundColor: t.field,
        foregroundColor: t.textSecondary,
        selectedBackgroundColor: t.accent,
        selectedForegroundColor: t.onAccent,
        side: BorderSide(color: t.fieldBorder),
        textStyle: labelStyle.copyWith(fontWeight: FontWeight.w500),
        enabledMouseCursor: GlowCursors.click,
        disabledMouseCursor: GlowCursors.basic,
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(menuColor)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.inverse,
      contentTextStyle: TextStyle(color: t.onInverse),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
