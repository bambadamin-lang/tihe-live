import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/src/ui/protection/watermark_overlay.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

void main() {
  const spec = WatermarkSpec(
    text: 'علی کریمی\n09121234503',
    opacity: 0.4,
    fontSize: 13,
    movement: 'corners',
    periodSeconds: 20,
    seed: 42,
  );
  // The overlay follows the same seeded sequence, so this is when it first jumps.
  final firstJump = WatermarkHopper(
    seed: spec.seed,
    periodSeconds: spec.periodSeconds,
  ).untilNext(Duration.zero);

  /// Shows the mark on a 1200×700 stage and returns a way to move its clock forward.
  Future<void Function(Duration)> pumpMark(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var now = DateTime.utc(2026, 10, 10, 9);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: WatermarkOverlay(spec: spec, clock: () => now),
        ),
      ),
    );
    return (by) => now = now.add(by);
  }

  /// Where the mark is drawn, by its phone row (outline layer), which moves with the whole mark.
  Rect mark(WidgetTester tester) =>
      tester.getRect(find.text('09121234503').first);

  testWidgets(
    'jumps to its next spot without crossing the stage, and lands with a bounce',
    (tester) async {
      final advance = await pumpMark(tester);
      // Nothing lands when the class opens: the mark is simply there.
      expect(tester.hasRunningAnimations, isFalse);
      final before = mark(tester);

      advance(firstJump);
      // The next tick sees the jump; this frame is the first of the move.
      await tester.pump(const Duration(seconds: 1));
      final landing = [mark(tester)];
      const frame = Duration(milliseconds: 16);
      for (var t = Duration.zero; t < Motion.slow; t += frame) {
        await tester.pump(frame);
        landing.add(mark(tester));
      }
      await tester.pumpAndSettle();
      final after = mark(tester);

      expect((after.center - before.center).distance, greaterThan(200));
      // Every frame of the move has it at its new spot, at most a little above it: never
      // anywhere between the two spots.
      for (final frame in landing) {
        expect(frame.left, after.left);
        expect(after.top - frame.top, inInclusiveRange(0, after.height));
      }
      // It comes down onto the spot rather than just appearing there.
      expect(landing.first.top, lessThan(after.top));
    },
  );

  testWidgets('with reduced motion it just appears in its next spot', (
    tester,
  ) async {
    final advance = await pumpMark(tester, reduceMotion: true);
    final before = mark(tester);

    advance(firstJump);
    await tester.pump(const Duration(seconds: 1));
    final after = mark(tester);

    expect((after.center - before.center).distance, greaterThan(200));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(Motion.slow);
    expect(mark(tester), after);
  });
}
