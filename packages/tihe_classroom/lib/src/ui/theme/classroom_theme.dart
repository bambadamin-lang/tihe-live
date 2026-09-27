import 'package:flutter/material.dart';

/// The classroom's skeuomorphic look (docs/11 §11): a walnut desk, cream paper, brushed
/// aluminium, brass plaques, enamel and glowing LEDs.
///
/// Every colour and depth the classroom widgets use comes from here, through a
/// [ThemeExtension] — so when an app-wide design system exists, it replaces this one object
/// and no widget changes.
@immutable
class ClassroomTheme extends ThemeExtension<ClassroomTheme> {
  const ClassroomTheme({
    this.woodDark = const Color(0xFF3B2515),
    this.woodMid = const Color(0xFF5A3923),
    this.woodLight = const Color(0xFF7A5234),
    this.paperHigh = const Color(0xFFF4EFE3),
    this.paperLow = const Color(0xFFD9CEB6),
    this.paperEdge = const Color(0xFFB5A686),
    this.ink = const Color(0xFF2A2118),
    this.inkSoft = const Color(0xFF6B5B47),
    this.brassHigh = const Color(0xFFF1D48E),
    this.brass = const Color(0xFFC9A45C),
    this.brassDark = const Color(0xFF8C6A2E),
    this.metalHigh = const Color(0xFFF4F5F6),
    this.metalMid = const Color(0xFFBAC0C7),
    this.metalLow = const Color(0xFF8C949C),
    this.enamel = const Color(0xFFFBFBF7),
    this.screenGlass = const Color(0xFF16120E),
    this.ledRed = const Color(0xFFE53935),
    this.ledGreen = const Color(0xFF43A047),
    this.ledAmber = const Color(0xFFFFB300),
    this.pinTeal = const Color(0xFF2F6F6A),
    this.pinPlum = const Color(0xFF7B3F61),
    this.pinNavy = const Color(0xFF2C4A7C),
    this.fontFamily = 'Peyda',
    this.fontFallback = const [
      'Vazirmatn',
      'Noto Sans Arabic',
      'Tahoma',
      'sans-serif',
    ],
  });

  final Color woodDark;
  final Color woodMid;
  final Color woodLight;
  final Color paperHigh;
  final Color paperLow;
  final Color paperEdge;
  final Color ink;
  final Color inkSoft;
  final Color brassHigh;
  final Color brass;
  final Color brassDark;
  final Color metalHigh;
  final Color metalMid;
  final Color metalLow;
  final Color enamel;
  final Color screenGlass;
  final Color ledRed;
  final Color ledGreen;
  final Color ledAmber;
  final Color pinTeal;
  final Color pinPlum;
  final Color pinNavy;
  final String fontFamily;
  final List<String> fontFallback;

  static ClassroomTheme of(BuildContext context) =>
      Theme.of(context).extension<ClassroomTheme>() ?? const ClassroomTheme();

  /// A raised object on the desk: a soft contact shadow and a longer cast shadow.
  List<BoxShadow> get raised => const [
    BoxShadow(color: Color(0x73000000), blurRadius: 22, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x59000000), blurRadius: 4, offset: Offset(0, 2)),
  ];

  /// Something small and physical: a button, a switch, a badge.
  List<BoxShadow> get lifted => const [
    BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x33000000), blurRadius: 1, offset: Offset(0, 1)),
  ];

  LinearGradient get paper => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [paperHigh, paperLow],
  );

  LinearGradient get metal => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [metalHigh, metalMid, metalLow],
    stops: const [0, 0.55, 1],
  );

  LinearGradient get brassPlate => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brassHigh, brass, brassDark, brass],
    stops: const [0, 0.35, 0.8, 1],
  );

  @override
  ClassroomTheme copyWith({String? fontFamily}) =>
      ClassroomTheme(fontFamily: fontFamily ?? this.fontFamily);

  @override
  ClassroomTheme lerp(ClassroomTheme? other, double t) => other ?? this;
}

/// The ThemeData the classroom runs under: Persian type, RTL-friendly components, and the
/// [ClassroomTheme] extension.
ThemeData buildClassroomThemeData([
  ClassroomTheme tokens = const ClassroomTheme(),
]) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: tokens.woodMid,
      primary: tokens.pinTeal,
      surface: tokens.paperHigh,
    ),
    fontFamily: tokens.fontFamily,
    fontFamilyFallback: tokens.fontFallback,
  );
  return base.copyWith(
    extensions: [tokens],
    textTheme: base.textTheme.apply(
      bodyColor: tokens.ink,
      displayColor: tokens.ink,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.ink.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: tokens.paperHigh,
        fontFamily: tokens.fontFamily,
        fontSize: 13,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.paperHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
