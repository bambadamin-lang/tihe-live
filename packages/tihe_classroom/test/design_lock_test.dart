import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// The design is locked (CLAUDE.md, hard rule 11; docs/11 §11). The institute chose this look,
/// and every version of every app keeps it, so these pins fail when it changes — on purpose. A
/// change the user asked for updates them in the same pull request: then it is a decision made
/// where reviewers see it, never the side effect of a merge or a refactor.
void main() {
  const why =
      'the design is locked (CLAUDE.md rule 11): change it only when the user asks';

  test(
    'the night sky, its planets and the blue accent, in dark and in light',
    () {
      final pins = {
        ClassroomTheme.dark: (
          canvas: const Color(0xFF060F22),
          canvasTop: const Color(0xFF0B1B3A),
          planet: const [
            Color(0xFF070D2B),
            Color(0xFF12246E),
            Color(0xFF2B4FE0),
            Color(0xFF7C9CFF),
          ],
          accent: const Color(0xFF2F6FFE),
          accentEnd: const Color(0xFF4A5BFF),
          text: const Color(0xFFF4F7FF),
          success: const Color(0xFF22DD95),
          danger: const Color(0xFFF0495E),
        ),
        ClassroomTheme.light: (
          canvas: const Color(0xFFEAF0FB),
          canvasTop: const Color(0xFFF6F9FF),
          planet: const [
            Color(0xFFDCE5FB),
            Color(0xFFB9CBF8),
            Color(0xFF7E9CF4),
            Color(0xFF4F74F0),
          ],
          accent: const Color(0xFF2563EB),
          accentEnd: const Color(0xFF4F46E5),
          text: const Color(0xFF0F1830),
          success: const Color(0xFF0FA36A),
          danger: const Color(0xFFE0334A),
        ),
      };
      for (final MapEntry(key: t, value: pin) in pins.entries) {
        expect(t.canvas, pin.canvas, reason: why);
        expect(t.canvasTop, pin.canvasTop, reason: why);
        expect(t.planet, pin.planet, reason: why);
        expect(t.accent, pin.accent, reason: why);
        expect(t.accentEnd, pin.accentEnd, reason: why);
        expect(t.text, pin.text, reason: why);
        expect(t.success, pin.success, reason: why);
        expect(t.danger, pin.danger, reason: why);
      }
    },
  );

  test('Modam', () {
    expect(ClassroomFonts.family, 'Modam', reason: why);
    for (final t in [ClassroomTheme.dark, ClassroomTheme.light]) {
      expect(t.fontFamily, 'Modam', reason: why);
      expect(
        buildClassroomThemeData(t).textTheme.bodyMedium?.fontFamily,
        'Modam',
        reason: why,
      );
    }
  });

  test('the glow cursor on everything clickable', () {
    final theme = buildClassroomThemeData(ClassroomTheme.dark);
    MouseCursor? resolve(ButtonStyle? style) =>
        style?.mouseCursor?.resolve(<WidgetState>{});
    expect(
      resolve(theme.filledButtonTheme.style),
      GlowCursors.click,
      reason: why,
    );
    expect(
      resolve(theme.outlinedButtonTheme.style),
      GlowCursors.click,
      reason: why,
    );
    expect(
      resolve(theme.textButtonTheme.style),
      GlowCursors.click,
      reason: why,
    );
    expect(
      resolve(theme.iconButtonTheme.style),
      GlowCursors.click,
      reason: why,
    );
    expect(
      theme.listTileTheme.mouseCursor?.resolve(<WidgetState>{}),
      GlowCursors.click,
      reason: why,
    );
    expect(GlowCursorArt.size, const Size(32, 38), reason: why);
  });

  testWidgets('the two-wedge mark and the name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClassroomThemeData(ClassroomTheme.dark),
        home: const Scaffold(body: Center(child: BrandLockup())),
      ),
    );
    expect(find.byType(BrandMark), findsOneWidget, reason: why);
    expect(
      find.text('TIHE Live', findRichText: true),
      findsOneWidget,
      reason: why,
    );
  });
}
