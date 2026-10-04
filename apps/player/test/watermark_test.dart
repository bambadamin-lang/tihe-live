import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_player/core/api/models.dart';
import 'package:tihe_player/features/player/watermark_overlay.dart';

/// The watermark is the mitigation for the attacker we cannot block (docs/08-threat-model.md, T3),
/// so these tests guard the properties that make it useful rather than decorative.
void main() {
  const watermark = Watermark(
    text: '0912•••6789 · #8B7C',
    opacity: 0.28,
    fontSize: 13,
    movement: 'drift',
    period: Duration(seconds: 47),
    seed: 918273,
  );

  Widget harness(Watermark mark) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: WatermarkOverlay(watermark: mark),
          ),
        ),
      );

  testWidgets('renders without throwing at a typical video size', (tester) async {
    await tester.pumpWidget(harness(watermark));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(WatermarkOverlay), findsOneWidget);
  });

  testWidgets('never intercepts pointer events', (tester) async {
    // A mark that swallows taps would break the player controls underneath it, and the obvious
    // "fix" would be to remove the mark.
    await tester.pumpWidget(harness(watermark));

    // Scoped to the overlay: Material's own scaffolding uses IgnorePointer too, so an unscoped
    // finder passes whether or not the watermark has one.
    expect(
      find.descendant(
        of: find.byType(WatermarkOverlay),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps animating, so the mark drifts', (tester) async {
    // A static mark is croppable out of an entire recording in one pass.
    await tester.pumpWidget(harness(watermark));

    await tester.pump(const Duration(seconds: 5));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('survives a degenerate size without throwing', (tester) async {
    // Happens during layout transitions and on a collapsed window; a crash here would take the
    // player down with it.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 4,
            height: 4,
            child: WatermarkOverlay(watermark: watermark),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a static watermark still renders', (tester) async {
    await tester.pumpWidget(
      harness(
        const Watermark(
          text: 'x',
          opacity: 0.3,
          fontSize: 12,
          movement: 'static',
          period: Duration(seconds: 47),
          seed: 1,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });
}
