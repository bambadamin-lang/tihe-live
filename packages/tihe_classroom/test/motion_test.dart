import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/src/ui/pods/chat_pod.dart';
import 'package:tihe_classroom/src/ui/pods/media_pods.dart';
import 'package:tihe_classroom/src/ui/whiteboard/board_painter.dart';
import 'package:tihe_classroom/src/ui/whiteboard/whiteboard_pod.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

import 'classroom_page_test.dart' show pumpClassroom;

RemotePreview preview({
  required List<int> points,
  int? revealFrom,
  String tool = 'pen',
  required DateTime at,
}) => RemotePreview(
  strokeId: 'wbi_1',
  from: 'usr_2',
  pageId: 'wbp_1',
  tool: tool,
  color: '#1D4ED8',
  width: 40,
  points: points,
  updatedAt: at,
  revealFrom: revealFrom,
);

void main() {
  group('a remote stroke glides in between batches', () {
    final at = DateTime.utc(2026, 9, 28, 10);
    // Two points on screen before this batch, four new ones in it.
    final points = [for (var i = 0; i < 12; i++) i * 100];

    test('starts from what was already shown', () {
      final p = preview(points: points, revealFrom: 4, at: at);
      expect(p.revealedAt(at), points.sublist(0, 4));
      expect(p.glidingAt(at), isTrue);
    });

    test(
      'reveals the batch across the preview interval, whole points only',
      () {
        final p = preview(points: points, revealFrom: 4, at: at);
        final half = at.add(BoardController.previewInterval ~/ 2);
        expect(p.revealedAt(half), points.sublist(0, 8));
        expect(p.revealedAt(half).length.isEven, isTrue);
      },
    );

    test(
      'is complete once the interval has passed, and stops asking for frames',
      () {
        final p = preview(points: points, revealFrom: 4, at: at);
        final later = at.add(BoardController.previewInterval);
        expect(p.revealedAt(later), points);
        expect(p.glidingAt(later), isFalse);
      },
    );

    test('a laser, or a preview without a reveal point, shows everything', () {
      expect(
        preview(
          points: points,
          revealFrom: 0,
          tool: 'laser',
          at: at,
        ).revealedAt(at),
        points,
      );
      expect(preview(points: points, at: at).revealedAt(at), points);
    });
  });

  group('the board repaints only the layer that changed', () {
    const page = BoardPage(id: 'wbp_1', background: BoardBackground.grid);
    final at = DateTime.utc(2026, 9, 28, 10);
    BoardPainter painter(
      BoardLayer layer, {
      List<RemotePreview> previews = const [],
      DateTime? now,
      Set<String> hidden = const {},
    }) => BoardPainter(
      layer: layer,
      page: page,
      items: const [],
      hidden: hidden,
      previews: previews,
      draft: null,
      now: now ?? at,
      fontFamily: 'Peyda',
    );

    test('ink in motion leaves the committed layer alone', () {
      final moving = [
        preview(points: const [0, 0, 100, 100], at: at),
      ];
      final later = at.add(const Duration(milliseconds: 16));
      expect(
        painter(
          BoardLayer.committed,
          previews: moving,
          now: later,
        ).shouldRepaint(painter(BoardLayer.committed)),
        isFalse,
      );
      expect(
        painter(
          BoardLayer.live,
          previews: moving,
          now: later,
        ).shouldRepaint(painter(BoardLayer.live)),
        isTrue,
      );
    });

    test('erasing repaints the committed layer', () {
      expect(
        painter(
          BoardLayer.committed,
          hidden: {'wbi_9'},
        ).shouldRepaint(painter(BoardLayer.committed)),
        isTrue,
      );
    });
  });

  testWidgets('with reduced motion, arrivals show at once', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Appear(child: Text('سلام')),
        ),
      ),
    );
    // No frame has passed: without motion there is nothing to wait for.
    expect(find.byType(Opacity), findsNothing);
    expect(find.text('سلام'), findsOneWidget);
  });

  testWidgets('an arrival fades in and then leaves no layers behind', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: Appear(child: Text('سلام')),
      ),
    );
    expect(find.byType(Opacity), findsOneWidget);
    await tester.pump(Motion.medium);
    await tester.pump();
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('maximise zooms a pod over the stage and restores it', (
    tester,
  ) async {
    await pumpClassroom(tester);
    await tester.pump(const Duration(seconds: 1));
    bool blocked(Type pod) => find
        .ancestor(
          of: find.byType(pod),
          matching: find.byWidgetPredicate(
            (w) => w is IgnorePointer && w.ignoring,
          ),
        )
        .evaluate()
        .isNotEmpty;

    final speaker = find.descendant(
      of: find.ancestor(
        of: find.byType(SpeakerPod),
        matching: find.byType(RepaintBoundary),
      ),
      matching: find.byTooltip('بزرگ کردن'),
    );
    await tester.tap(speaker.first);
    await tester.pump(Motion.slow);
    await tester.pump();
    // The other pods stay mounted (their state survives) but fade and take no input.
    expect(find.byType(ChatPod), findsOneWidget);
    expect(blocked(ChatPod), isTrue);
    expect(blocked(WhiteboardPod), isTrue);
    expect(blocked(SpeakerPod), isFalse);

    await tester.tap(find.byTooltip('بازگشت به چیدمان'));
    await tester.pump(Motion.slow);
    await tester.pump();
    expect(blocked(ChatPod), isFalse);
    expect(blocked(WhiteboardPod), isFalse);
  });
}
