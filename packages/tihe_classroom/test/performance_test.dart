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

MediaState _speaking(MediaState state, String speaker) => MediaState(
  connected: true,
  activeSpeaker: speaker,
  participants: {
    for (final m in state.participants.values)
      m.userId: ParticipantMedia(
        userId: m.userId,
        micOn: m.micOn,
        cameraOn: m.cameraOn,
        screenOn: m.screenOn,
        speaking: m.userId == speaker,
        isLocal: m.isLocal,
      ),
  },
);

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

    testWidgets(
      'a change of speaker redraws the tiles involved, not the gallery or the dock',
      (tester) async {
        final demo = await _open(tester);
        final counts = await _rebuilds(() async {
          demo.media.emit(_speaking(demo.media.state, DemoClassroom.sara));
          await tester.pump(const Duration(milliseconds: 100));
        });
        // Two tiles: the host stops speaking, Sara starts. The speaker pod shows the host,
        // whose strip changes too.
        expect(counts['_Tile'], 2);
        expect(_podsRebuilt(counts, allowed: {'SpeakerPod'}), isEmpty);
      },
    );

    testWidgets('a chat message rebuilds the chat and nothing else', (
      tester,
    ) async {
      final demo = await _open(tester);
      final counts = await _rebuilds(() async {
        demo.server.emit(
          ChatPosted(
            ChatMessage(
              id: 'chm_01J9PF00000000000000000009',
              userId: DemoClassroom.sara,
              name: 'سارا محمدی',
              role: ClassRole.participant,
              text: 'سلام',
              at: DateTime.now().toUtc().toIso8601String(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      });
      expect(counts['ChatPod'], 1);
      expect(_podsRebuilt(counts, allowed: {'ChatPod'}), isEmpty);
    });

    testWidgets(
      'a raised hand rebuilds the queue and the participant who raised it',
      (tester) async {
        final demo = await _open(tester, layout: LayoutPreset.discussion);
        final p = demo.server.state.participants[DemoClassroom.sara]!;
        final counts = await _rebuilds(() async {
          demo.server.emit(
            ParticipantUpdated(
              ParticipantState(
                userId: p.userId,
                name: p.name,
                role: p.role,
                caps: p.caps,
                grants: p.grants,
                revokes: p.revokes,
                hand: Hand(
                  raisedSeq: demo.server.state.seq + 1,
                  raisedAt: DateTime.now().toUtc().toIso8601String(),
                ),
                floor: p.floor,
                online: p.online,
                capturing: p.capturing,
                joinedAt: p.joinedAt,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
        });
        expect(counts['HandsPod'], 1);
        expect(counts['_Tile'], 1, reason: 'her tile shows the hand');
        expect(_podsRebuilt(counts, allowed: {'HandsPod'}), isEmpty);
      },
    );

    testWidgets('the participant list rebuilds only the card that changed', (
      tester,
    ) async {
      final demo = await _open(tester, layout: LayoutPreset.lecture);
      final counts = await _rebuilds(() async {
        demo.media.emit(_speaking(demo.media.state, DemoClassroom.sara));
        await tester.pump(const Duration(milliseconds: 100));
        final s = demo.media.state;
        demo.media.emit(
          MediaState(
            connected: true,
            activeSpeaker: s.activeSpeaker,
            participants: {
              ...s.participants,
              DemoClassroom.ali: ParticipantMedia(
                userId: DemoClassroom.ali,
                micOn: true,
                cameraOn: true,
                isLocal: true,
              ),
            },
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
      });
      // Speaking is not shown in the list; Ali's microphone is, on his card and in the dock.
      expect(counts['ParticipantsPod'], isNull);
      expect(counts['_Card'], 1);
      expect(counts['ControlBar'], 1);
    });
  });

  testWidgets('an idle class asks for a few frames a second, not one per vsync', (
    tester,
  ) async {
    // The demo class is being recorded, so its lamp breathes, and the clock ticks.
    await _open(tester, as: DemoClassroom.host);
    const vsync = Duration(microseconds: 16667);
    var frames = 0;
    for (var tick = 0; tick < 300; tick++) {
      if (tester.binding.hasScheduledFrame) {
        frames++;
        await tester.pump(vsync);
      } else {
        await tester.binding.delayed(vsync);
      }
    }
    // Five seconds at 60 Hz: the lamp steps 15 times a second and the clock once.
    expect(frames / 5, lessThanOrEqualTo(17));
    expect(
      frames / 5,
      greaterThanOrEqualTo(10),
      reason: 'the lamp still breathes',
    );
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
