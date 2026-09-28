import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/src/domain/board_model.dart';
import 'package:tihe_classroom/src/domain/stage_geometry.dart';
import 'package:tihe_classroom/src/ui/whiteboard/board_painter.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

SequencedEvent evt(int seq, ClassroomEvent e) =>
    SequencedEvent(seq: seq, at: '2026-09-27T07:00:00.000Z', event: e);

void main() {
  group('ClassroomState.apply', () {
    final start = ClassroomState.fromSnapshot(DemoClassroom.snapshot(), 20);

    test(
      'ignores events it has already applied, so an overlapping replay is harmless',
      () {
        final next = start.apply(
          evt(20, const BoardPageCleared(DemoClassroom.page1)),
        );
        expect(identical(next, start), isTrue);
      },
    );

    test('updates a participant in place and keeps join order', () {
      final ali = start.participants[DemoClassroom.ali]!;
      final updated = ParticipantState.fromJson({
        ...ali.toJson(),
        'hand': null,
      });
      final next = start.apply(evt(21, ParticipantUpdated(updated)));
      expect(next.participants[DemoClassroom.ali]!.hand, isNull);
      expect(next.participants.keys, start.participants.keys);
      expect(next.seq, 21);
    });

    test('orders raised hands by the server sequence', () {
      expect(start.raisedHands.map((p) => p.name), ['علی کریمی', 'رضا نوری']);
    });

    test('removes a participant', () {
      final next = start.apply(
        evt(21, const ParticipantRemoved(DemoClassroom.sara, null)),
      );
      expect(next.participants.containsKey(DemoClassroom.sara), isFalse);
    });

    test('clears a page and removes a page with its items', () {
      final cleared = start.apply(
        evt(21, const BoardPageCleared(DemoClassroom.page1)),
      );
      expect(cleared.itemsOn(DemoClassroom.page1), isEmpty);
      expect(cleared.pages, hasLength(2));
      final removed = start.apply(
        evt(21, const BoardPageRemoved(DemoClassroom.page2)),
      );
      expect(removed.pages.map((p) => p.id), [DemoClassroom.page1]);
    });

    test('keeps at most 200 chat messages', () {
      var s = start;
      for (var i = 0; i < 210; i++) {
        s = s.apply(
          evt(
            21 + i,
            ChatPosted(
              ChatMessage(
                id: 'chm_$i',
                userId: DemoClassroom.ali,
                name: 'علی',
                role: ClassRole.participant,
                text: '$i',
                at: '2026-09-27T07:00:00.000Z',
              ),
            ),
          ),
        );
      }
      expect(s.chat, hasLength(ClassroomState.chatLimit));
      expect(s.chat.last.text, '209');
    });

    test('marks the class ended', () {
      final next = start.apply(evt(21, const ClassEnded('host_ended')));
      expect(next.ended, isTrue);
      expect(next.endReason, 'host_ended');
    });

    test('round-trips through a snapshot', () {
      final again = ClassroomState.fromSnapshot(start.toSnapshot(), start.seq);
      expect(again.toSnapshot().toJson(), start.toSnapshot().toJson());
    });
  });

  group('WatermarkHopper', () {
    test('is deterministic for a seed', () {
      final a = WatermarkHopper(seed: 42, periodSeconds: 30);
      final b = WatermarkHopper(seed: 42, periodSeconds: 30);
      for (var s = 0; s < 600; s += 7) {
        expect(
          a.cornerAt(Duration(seconds: s)),
          b.cornerAt(Duration(seconds: s)),
        );
      }
    });

    test('visits every corner and never jumps to the corner it is in', () {
      final hopper = WatermarkHopper(seed: 7, periodSeconds: 20);
      final seen = <StageCorner>{};
      StageCorner? previous;
      var jumps = 0;
      for (var s = 0; s < 1200; s++) {
        final c = hopper.cornerAt(Duration(seconds: s));
        seen.add(c);
        if (previous != null && c != previous) jumps++;
        previous = c;
      }
      expect(seen, StageCorner.values.toSet());
      // 1200 s at 10–30 s per stay: dozens of jumps, never zero.
      expect(jumps, greaterThan(30));
    });

    test(
      'keeps a floor on the period so a bad value cannot make it flicker',
      () {
        final hopper = WatermarkHopper(seed: 1, periodSeconds: 0);
        expect(
          hopper.untilNext(Duration.zero),
          greaterThanOrEqualTo(const Duration(seconds: 2)),
        );
      },
    );
  });

  group('StageGeometry', () {
    final lecture = layoutPresets[LayoutPreset.lecture]!;

    test('puts grid column 0 on the right in RTL', () {
      final rects = StageGeometry.grid(
        lecture,
        const Size(1200, 1200),
        direction: TextDirection.rtl,
        gap: 0,
      );
      expect(rects['speaker']!.right, 1200);
      expect(rects['chat']!.left, 0);
      final ltr = StageGeometry.grid(
        lecture,
        const Size(1200, 1200),
        direction: TextDirection.ltr,
        gap: 0,
      );
      expect(ltr['speaker']!.left, 0);
    });

    test('shows the biggest content pod first on a phone', () {
      expect(
        StageGeometry.primary(layoutPresets[LayoutPreset.split]!).kind,
        PodKind.screen,
      );
      expect(
        StageGeometry.primary(layoutPresets[LayoutPreset.discussion]!).kind,
        PodKind.gallery,
      );
      expect(StageGeometry.tabs(lecture).first.kind, PodKind.speaker);
    });

    test('switches to one pod at a time under 600 wide', () {
      expect(StageGeometry.isCompact(const Size(599, 900)), isTrue);
      expect(StageGeometry.isCompact(const Size(600, 900)), isFalse);
    });
  });

  group('whiteboard model', () {
    StrokeItem stroke(
      String id,
      List<int> points, {
      String by = DemoClassroom.host,
    }) => StrokeItem(
      id: id,
      pageId: DemoClassroom.page1,
      color: '#1B1B1F',
      tool: PenTool.pen,
      width: 30,
      points: points,
      by: by,
    );

    test('maps the widget to the 16:9 page, letterboxed and clamped', () {
      final v = BoardViewport(const Size(1600, 1000));
      expect(v.page, const Rect.fromLTWH(0, 50, 1600, 900));
      expect(v.toPage(const Offset(800, 500)), (x: 8000, y: 4500));
      expect(v.toPage(const Offset(-50, 2000)), (x: 0, y: 9000));
    });

    test('the eraser hits strokes near their segments, not far away', () {
      final item = stroke('a', [0, 0, 1000, 0]);
      expect(eraserHits(item, (x: 500, y: 100)), isTrue);
      expect(eraserHits(item, (x: 500, y: 400)), isFalse);
    });

    test(
      'the eraser hits a rectangle on its edge, and inside only when filled',
      () {
        const hollow = ShapeItem(
          id: 'r',
          pageId: 'p',
          color: '#000000',
          shape: ShapeKind.rect,
          width: 20,
          fill: null,
          from: (x: 0, y: 0),
          to: (x: 4000, y: 4000),
        );
        expect(eraserHits(hollow, (x: 2000, y: 2000)), isFalse);
        expect(eraserHits(hollow, (x: 2000, y: 50)), isTrue);
        const filled = ShapeItem(
          id: 'r',
          pageId: 'p',
          color: '#000000',
          shape: ShapeKind.rect,
          width: 20,
          fill: '#FFFFFF',
          from: (x: 0, y: 0),
          to: (x: 4000, y: 4000),
        );
        expect(eraserHits(filled, (x: 2000, y: 2000)), isTrue);
      },
    );

    test('undo removes what was added, redo puts it back', () {
      final history = BoardHistory();
      final item = stroke('wbi_x', [0, 0, 10, 10]);
      history.record(ItemsAdded([item]));
      final undo = history.undo();
      expect(
        undo,
        isA<RemoveBoardItems>().having((c) => c.itemIds, 'ids', ['wbi_x']),
      );
      final redo = history.redo();
      expect(
        redo,
        isA<RestoreBoardItems>().having(
          (c) => c.items.single.id,
          'id',
          'wbi_x',
        ),
      );
      expect(history.canRedo, isFalse);
    });

    test('undoing an erase restores the erased items', () {
      final history = BoardHistory()
        ..record(
          ItemsRemoved([
            stroke('a', [0, 0, 1, 1]),
          ]),
        );
      expect(history.undo(), isA<RestoreBoardItems>());
    });

    test('a new action clears the redo stack', () {
      final history = BoardHistory()
        ..record(
          ItemsAdded([
            stroke('a', [0, 0, 1, 1]),
          ]),
        );
      history.undo();
      history.record(
        ItemsAdded([
          stroke('b', [0, 0, 1, 1]),
        ]),
      );
      expect(history.canRedo, isFalse);
    });

    test('splits a long stroke into joined pieces within the point limit', () {
      final points = [
        for (var i = 0; i < 5000; i++) ...[i, i % 9000],
      ];
      final pieces = splitStroke(points);
      expect(pieces.every((p) => p.length <= maxStrokePoints * 2), isTrue);
      for (var i = 1; i < pieces.length; i++) {
        final prev = pieces[i - 1];
        expect(pieces[i].sublist(0, 2), prev.sublist(prev.length - 2));
      }
    });

    test('text reads in its own direction', () {
      expect(textDirectionOf('مشتق توابع مرکب'), TextDirection.rtl);
      expect(textDirectionOf("(f(g(x)))′ = f′(g(x))"), TextDirection.ltr);
      expect(textDirectionOf('مثال: y = sin(x²)'), TextDirection.rtl);
    });
  });

  test('Persian digits and Jalali dates', () {
    expect(toPersianDigits('12:05'), '۱۲:۰۵');
    expect(jalaliDate(DateTime.utc(2026, 9, 27, 8)), '۵ مهر ۱۴۰۵');
    expect(
      elapsedClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '۰۱:۰۲:۰۳',
    );
  });
}
