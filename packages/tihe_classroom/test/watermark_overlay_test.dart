import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/src/ui/protection/watermark_overlay.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// The identity watermark as the institute asked for it (docs/11 §9): the viewer's name with
/// their whole phone number beneath it, nothing else, jumping between the four corners and the
/// centre of the stage.
void main() {
  const spec = WatermarkSpec(
    text: 'علی کریمی\n09121234503',
    opacity: 0.4,
    fontSize: 13,
    movement: 'corners-and-center',
    periodSeconds: 20,
    seed: 42,
  );
  const name = 'علی کریمی';
  const phone = '09121234503';

  WatermarkHopper hopperFor(WatermarkSpec spec) => WatermarkHopper(
    seed: spec.seed,
    periodSeconds: spec.periodSeconds,
    spots: WatermarkHopper.spotsFor(spec.movement),
  );
  // The overlay follows the same seeded sequence, so this is when it first jumps.
  final firstJump = hopperFor(spec).untilNext(Duration.zero);

  /// Shows the mark on a 1200×700 stage; the returned function moves its time forward.
  Future<void Function(Duration)> pumpMark(
    WidgetTester tester, {
    WatermarkSpec spec = spec,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var elapsed = Duration.zero;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: WatermarkOverlay(spec: spec, elapsed: () => elapsed),
        ),
      ),
    );
    return (by) => elapsed += by;
  }

  Finder inMark(Finder f) =>
      find.descendant(of: find.byType(WatermarkOverlay), matching: f);

  /// Where the mark is drawn, by its phone row (outline layer), which moves with the whole mark.
  Rect mark(WidgetTester tester) => tester.getRect(find.text(phone).first);

  AlignmentGeometry spotOf(WidgetTester tester) =>
      tester.widget<Align>(inMark(find.byType(Align)).first).alignment;

  /// Lets [by] pass on the mark's clock and in the test's, landing included.
  Future<void> pass(
    WidgetTester tester,
    void Function(Duration) advance,
    Duration by,
  ) async {
    advance(by);
    await tester.pump(by);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'prints the name with the whole number beneath it, and nothing else',
    (tester) async {
      await pumpMark(tester);
      // Outline and fill: two layers of each row, and no other text.
      expect(inMark(find.text(name)), findsNWidgets(2));
      expect(inMark(find.text(phone)), findsNWidgets(2));
      expect(inMark(find.byType(Text)), findsNWidgets(4));
      final nameRect = tester.getRect(inMark(find.text(name)).first);
      expect(mark(tester).top, greaterThanOrEqualTo(nameRect.bottom));
      for (final t in tester.widgetList<Text>(inMark(find.byType(Text)))) {
        expect(t.data, isNot(contains('#')));
        expect(t.data, isNot(contains('•')));
        expect(t.data, isNot(matches(RegExp(r'\d{1,2}:\d{2}'))));
        // A Persian name reads right to left; the number left to right, so no digit reorders.
        expect(
          t.textDirection,
          t.data == name ? TextDirection.rtl : TextDirection.ltr,
        );
      }
    },
  );

  testWidgets('a number alone is one row', (tester) async {
    await pumpMark(
      tester,
      spec: const WatermarkSpec(
        text: phone,
        opacity: 0.4,
        fontSize: 13,
        movement: 'corners-and-center',
        periodSeconds: 20,
        seed: 1,
      ),
    );
    expect(inMark(find.byType(Text)), findsNWidgets(2));
    expect(inMark(find.text(phone)), findsNWidgets(2));
  });

  testWidgets('jumps between all four corners and the centre', (tester) async {
    final advance = await pumpMark(tester);
    final seen = <AlignmentGeometry>{spotOf(tester)};
    for (var i = 0; i < 120; i++) {
      await pass(tester, advance, const Duration(seconds: 3));
      seen.add(spotOf(tester));
    }
    expect(seen, {
      AlignmentDirectional.topStart,
      AlignmentDirectional.topEnd,
      AlignmentDirectional.center,
      AlignmentDirectional.bottomStart,
      AlignmentDirectional.bottomEnd,
    });
  });

  testWidgets('a server that asks for corners gets the corners only', (
    tester,
  ) async {
    final advance = await pumpMark(
      tester,
      spec: const WatermarkSpec(
        text: phone,
        opacity: 0.4,
        fontSize: 13,
        movement: 'corners',
        periodSeconds: 20,
        seed: 42,
      ),
    );
    final seen = <AlignmentGeometry>{spotOf(tester)};
    for (var i = 0; i < 120; i++) {
      await pass(tester, advance, const Duration(seconds: 3));
      seen.add(spotOf(tester));
    }
    expect(seen, isNot(contains(AlignmentDirectional.center)));
    expect(seen, hasLength(4));
  });

  testWidgets('jumps within a second of when it is due, and not before', (
    tester,
  ) async {
    final advance = await pumpMark(tester);
    final before = spotOf(tester);
    await pass(tester, advance, firstJump - const Duration(seconds: 1));
    expect(spotOf(tester), before);
    await pass(tester, advance, const Duration(seconds: 2));
    expect(spotOf(tester), isNot(before));
  });

  testWidgets('both rows hug the spot they are in', (tester) async {
    final advance = await pumpMark(tester);
    final checked = <AlignmentGeometry>{};
    for (var i = 0; i < 120 && checked.length < 5; i++) {
      final spot = spotOf(tester);
      final n = tester.getRect(inMark(find.text(name)).first);
      final p = mark(tester);
      // In right to left, a start corner is on the right.
      if (spot == AlignmentDirectional.center) {
        expect(n.center.dx, moreOrLessEquals(p.center.dx, epsilon: 0.5));
      } else if (spot == AlignmentDirectional.topStart ||
          spot == AlignmentDirectional.bottomStart) {
        expect(n.right, moreOrLessEquals(p.right, epsilon: 0.5));
      } else {
        expect(n.left, moreOrLessEquals(p.left, epsilon: 0.5));
      }
      checked.add(spot);
      await pass(tester, advance, const Duration(seconds: 3));
    }
    expect(checked, hasLength(5));
  });

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

  // The class may be watching this viewer's window while they share their own screen.
  testWidgets('masks the number while the viewer shares their own screen', (
    tester,
  ) async {
    Widget overlay({required bool sharing}) => Directionality(
      textDirection: TextDirection.rtl,
      child: WatermarkOverlay(spec: spec, ownShare: sharing),
    );
    await tester.pumpWidget(overlay(sharing: true));
    expect(inMark(find.text(name)), findsNWidgets(2));
    expect(inMark(find.text('0912•••4503')), findsNWidgets(2));
    expect(inMark(find.textContaining('1234503')), findsNothing);

    await tester.pumpWidget(overlay(sharing: false));
    expect(inMark(find.text(phone)), findsNWidgets(2));
    expect(inMark(find.textContaining('•')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps its own time when no test clock is given', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: WatermarkOverlay(spec: spec),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(inMark(find.text(phone)), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });
}
