import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/src/ui/protection/watermark_overlay.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// The identity watermark as the institute asked for it (docs/11 §9): the viewer's name over
/// their whole phone number, nothing else, jumping between the four corners and the centre.
void main() {
  const spec = WatermarkSpec(
    text: 'مریم احمدی\n09123456789',
    opacity: 0.32,
    fontSize: 13,
    movement: 'corners-and-center',
    periodSeconds: 10,
    seed: 918273,
  );

  Future<Future<void> Function(Duration)> pumpMark(
    WidgetTester tester,
    WatermarkSpec spec,
  ) async {
    var now = DateTime.utc(2026, 10, 18, 9);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: WatermarkOverlay(spec: spec, clock: () => now),
      ),
    );
    return (step) async {
      now = now.add(step);
      await tester.pump(step);
    };
  }

  Align markAlign(WidgetTester tester) => tester.widget<Align>(
    find.ancestor(of: find.byType(Opacity), matching: find.byType(Align)).first,
  );

  testWidgets(
    'prints the name over the whole number, with no id and no clock',
    (tester) async {
      await pumpMark(tester, spec);
      // Outline and fill: two layers of exactly the text it was given.
      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts, hasLength(2));
      for (final t in texts) {
        expect(t.data, 'مریم احمدی\n09123456789');
        expect(t.data!.split('\n').first, 'مریم احمدی');
        expect(t.data, isNot(contains('#')));
        expect(t.data, isNot(matches(RegExp(r'\d{1,2}:\d{2}'))));
        expect(t.textAlign, TextAlign.center);
        expect(t.textDirection, TextDirection.rtl);
      }
    },
  );

  testWidgets('a number alone stays left to right', (tester) async {
    await pumpMark(
      tester,
      const WatermarkSpec(
        text: '09123456789',
        opacity: 0.32,
        fontSize: 13,
        movement: 'corners-and-center',
        periodSeconds: 10,
        seed: 1,
      ),
    );
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.textDirection, TextDirection.ltr);
    }
  });

  testWidgets('jumps between the four corners and the centre, never sliding', (
    tester,
  ) async {
    final advance = await pumpMark(tester, spec);
    expect(find.byType(AnimatedAlign), findsNothing);
    final seen = <AlignmentGeometry>{markAlign(tester).alignment};
    for (var i = 0; i < 120; i++) {
      await advance(const Duration(seconds: 3));
      seen.add(markAlign(tester).alignment);
    }
    expect(seen, {
      AlignmentDirectional.topStart,
      AlignmentDirectional.topEnd,
      AlignmentDirectional.center,
      AlignmentDirectional.bottomStart,
      AlignmentDirectional.bottomEnd,
    });
  });

  testWidgets('moves exactly when the hopper says, and not before', (
    tester,
  ) async {
    final advance = await pumpMark(tester, spec);
    final hopper = WatermarkHopper(
      seed: spec.seed,
      periodSeconds: spec.periodSeconds,
      spots: WatermarkHopper.spotsFor(spec.movement),
    );
    final wait = hopper.untilNext(Duration.zero);
    final before = markAlign(tester).alignment;
    await advance(wait - const Duration(milliseconds: 100));
    expect(markAlign(tester).alignment, before);
    await advance(const Duration(milliseconds: 200));
    expect(markAlign(tester).alignment, isNot(before));
  });

  testWidgets('a server that asks for corners gets corners only', (
    tester,
  ) async {
    final advance = await pumpMark(
      tester,
      const WatermarkSpec(
        text: '09123456789',
        opacity: 0.32,
        fontSize: 13,
        movement: 'corners',
        periodSeconds: 10,
        seed: 918273,
      ),
    );
    final seen = <AlignmentGeometry>{markAlign(tester).alignment};
    for (var i = 0; i < 120; i++) {
      await advance(const Duration(seconds: 3));
      seen.add(markAlign(tester).alignment);
    }
    expect(seen, isNot(contains(AlignmentDirectional.center)));
    expect(seen, hasLength(4));
  });
}
