import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/src/domain/board_model.dart';
import 'package:tihe_classroom/src/ui/whiteboard/board_painter.dart';
import 'package:tihe_classroom/src/ui/whiteboard/committed_ink.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// Guards for the classroom's performance (docs/11 §11): what may rebuild when the class
/// changes, how many frames an idle class asks for, and what the board works out again.
/// These fail silently in use — the app just gets slower — so they are pinned here.

typedef _Demo = ({
  ClassroomSession session,
  DemoClassroomServer server,
  FakeClassroomMedia media,
});

Future<_Demo> _open(
  WidgetTester tester, {
  String as = DemoClassroom.ali,
  LayoutPreset layout = LayoutPreset.split,
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final demo = DemoClassroom.build(as: as, layout: layoutPresets[layout]);
  await tester.pumpWidget(
    MaterialApp(
      home: ClassroomPage(session: demo.session, brightness: Brightness.dark),
    ),
  );
  // Past every arrival animation.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  return demo;
}

/// How many times each widget type rebuilt while [body] ran.
Future<Map<String, int>> _rebuilds(Future<void> Function() body) async {
  final counts = <String, int>{};
  debugOnRebuildDirtyWidget = (element, _) {
    final type = element.widget.runtimeType.toString();
    counts[type] = (counts[type] ?? 0) + 1;
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}

const _pods = [
  'ControlBar',
  'TopBar',
  'SpeakerPod',
  'GalleryPod',
  'ScreenPod',
  'ParticipantsPod',
  'HandsPod',
  'ChatPod',
  'BoardCanvas',
  'MarkerTray',
  'StageView',
];

/// The pods among [counts] that rebuilt, other than [allowed].
Map<String, int> _podsRebuilt(
  Map<String, int> counts, {
  Set<String> allowed = const {},
}) => {
  for (final pod in _pods)
    if ((counts[pod] ?? 0) > 0 && !allowed.contains(pod)) pod: counts[pod]!,
};

void main() {
  group('a busy class rebuilds only what changed', () {
    testWidgets('a remote stroke preview rebuilds the board and nothing else', (
      tester,
    ) async {
      final demo = await _open(tester);
      final counts = await _rebuilds(() async {
        for (var i = 0; i < 10; i++) {
          demo.server.relay(
            DemoClassroom.host,
            BoardProgress(
              strokeId: 'wbi_01J9PF00000000000000000001',
              pageId: DemoClassroom.page1,
              tool: 'pen',
              color: '#1F4FD8',
              width: 30,
              points: [1000 + i * 50, 4000, 1020 + i * 50, 4010],
              done: false,
            ),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }
      });
      expect(counts['BoardCanvas'], greaterThan(0));
      expect(_podsRebuilt(counts, allowed: {'BoardCanvas'}), isEmpty);
    });

    testWidgets('a media report that changes nothing rebuilds nothing', (
      tester,
    ) async {
      final demo = await _open(tester);
      final counts = await _rebuilds(() async {
        for (var i = 0; i < 10; i++) {
          final s = demo.media.state;
          demo.media.emit(
            MediaState(
              connected: s.connected,
              activeSpeaker: s.activeSpeaker,
              participants: {...s.participants},
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
      expect(_podsRebuilt(counts), isEmpty);
    });
  });

  testWidgets('erased strokes leave the board while the eraser is still down', (
    tester,
  ) async {
    final demo = await _open(
      tester,
      as: DemoClassroom.host,
      layout: LayoutPreset.whiteboard,
    );
    BoardPainter committed() =>
        tester.widget<CommittedInk>(find.byType(CommittedInk)).painter;

    demo.session.board.selectTool(BoardTool.eraser);
    await tester.pump();
    final before = committed();
    // The axis line drawn from (900, 8200) to (5900, 8200) on the page.
    const axis = 'wbi_01J8ZE00000000000000000001';
    final canvas = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'BoardCanvas',
    );
    final box = tester.getRect(canvas);
    final at = BoardViewport(box.size).toLocal(3000, 8200) + box.topLeft;
    final pen = await tester.startGesture(at);
    await pen.moveBy(const Offset(4, 0));
    await tester.pump();

    final during = committed();
    expect(during.hidden, contains(axis));
    expect(before.hidden, isNot(contains(axis)));
    expect(during.shouldRepaint(before), isTrue);
    await pen.up();
    await tester.pump();
  });

  testWidgets(
    'finished ink is drawn from an image while the board is still, and directly while it moves',
    (tester) async {
      await _open(
        tester,
        as: DemoClassroom.host,
        layout: LayoutPreset.whiteboard,
      );
      RenderCommittedInk ink() =>
          tester.renderObject<RenderCommittedInk>(find.byType(CommittedInk));
      expect(ink().showingImage, isTrue);

      // Maximise glides the board across the stage: drawn directly on the way.
      final panel = find.ancestor(
        of: find.byType(CommittedInk),
        matching: find.byType(GlassPanel),
      );
      await tester.tap(
        find.descendant(of: panel, matching: find.byTooltip('بزرگ کردن')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(ink().showingImage, isFalse);

      // At rest again: back to an image, made for the new size.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ink().showingImage, isTrue);
    },
  );

  test(
    'a finished stroke is outlined once, however often the page repaints',
    () {
      final stroke = DemoClassroom.boardItems.whereType<StrokeItem>().last;
      expect(
        identical(
          BoardPainter.outlineOf(stroke),
          BoardPainter.outlineOf(stroke),
        ),
        isTrue,
      );
    },
  );
}
