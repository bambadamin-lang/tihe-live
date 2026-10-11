import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/src/ui/controls/bars.dart';
import 'package:tihe_classroom/src/ui/pods/chat_pod.dart';
import 'package:tihe_classroom/src/ui/pods/media_pods.dart';
import 'package:tihe_classroom/src/ui/pods/person_actions.dart';
import 'package:tihe_classroom/src/ui/whiteboard/whiteboard_pod.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

import 'classroom_page_test.dart' show pumpClassroom;

/// What a frame costs: work the class does for things nobody sees is work taken from video and
/// ink on a student's laptop or phone.
void main() {
  testWidgets(
    'ink from the teacher redraws the board, not the dock or the speaker',
    (tester) async {
      final c = await pumpClassroom(tester, as: DemoClassroom.ali);
      final built = await rebuildsWhileDrawing(tester, c.server);
      expect(built[BoardCanvas], greaterThan(0), reason: 'the ink arrived');
      for (final type in [ControlBar, SpeakerPod, ParticipantMenuButton]) {
        expect(built[type], isNull, reason: '$type rebuilt for ink');
      }
    },
  );

  testWidgets('ink does not rebuild a chat that hides private messages', (
    tester,
  ) async {
    // A co-host holds a student's private question, then is made a participant: from then on
    // their chat leaves it out, and that filtered chat must not be rebuilt for each ink batch.
    final c = await pumpClassroom(tester, as: DemoClassroom.cohost);
    c.server.emit(
      ChatPosted(
        ChatMessage(
          id: 'chm_private',
          userId: DemoClassroom.ali,
          name: 'علی',
          role: ClassRole.participant,
          text: 'سوال خصوصی',
          at: '2026-10-11T07:00:00.000Z',
          isPrivate: true,
        ),
      ),
    );
    final cohost = c.server.state.participants[DemoClassroom.cohost]!;
    c.server.emit(
      ParticipantUpdated(
        ParticipantState.fromJson({
          ...cohost.toJson(),
          'role': 'participant',
          'caps': ['chat.send', 'hand.raise'],
        }),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('سوال خصوصی'),
      findsNothing,
      reason: 'hidden once demoted',
    );

    final built = await rebuildsWhileDrawing(tester, c.server);
    expect(built[BoardCanvas], greaterThan(0), reason: 'the ink arrived');
    expect(built[ChatPod], isNull, reason: 'the chat rebuilt for ink');
  });

  for (final preset in [LayoutPreset.discussion, LayoutPreset.split]) {
    testWidgets('a gallery tile keeps its video when the order changes '
        '(${preset.wire})', (tester) async {
      final c = await pumpClassroom(
        tester,
        as: DemoClassroom.ali,
        layout: layoutPresets[preset],
      );
      Element video(String userId) => tester.element(
        find.byWidgetPredicate(
          (w) =>
              w is DemoVideo &&
              w.userId == userId &&
              w.slot == VideoSlot.camera,
        ),
      );
      final cohost = video(DemoClassroom.cohost);

      // The co-host starts talking and moves to the front, ahead of the host.
      final now = c.media.state;
      c.media.emit(
        MediaState(
          connected: true,
          activeSpeaker: DemoClassroom.cohost,
          participants: {
            ...now.participants,
            DemoClassroom.host: const ParticipantMedia(
              userId: DemoClassroom.host,
              micOn: true,
              cameraOn: true,
            ),
            DemoClassroom.cohost: const ParticipantMedia(
              userId: DemoClassroom.cohost,
              micOn: true,
              cameraOn: true,
              speaking: true,
            ),
          },
        ),
      );
      await tester.pump();

      // The same element: a live renderer moved, not torn down and attached again.
      expect(identical(video(DemoClassroom.cohost), cohost), isTrue);
    });
  }
}

/// Which widgets rebuild, and how often, during a second of the host drawing: a batch every
/// 40 ms (docs/11 §6).
Future<Map<Type, int>> rebuildsWhileDrawing(
  WidgetTester tester,
  DemoClassroomServer server,
) async {
  // Let the class finish arriving: the first layout brings its pods in one by one.
  await tester.pump(const Duration(seconds: 2));
  final built = <Type, int>{};
  debugOnRebuildDirtyWidget = (element, _) =>
      built.update(element.widget.runtimeType, (n) => n + 1, ifAbsent: () => 1);
  try {
    for (var i = 0; i < 25; i++) {
      server.relay(
        DemoClassroom.host,
        BoardProgress(
          strokeId: 'wbi_ink',
          pageId: DemoClassroom.page1,
          tool: 'pen',
          color: '#1D4ED8',
          width: 4,
          points: [i * 10, 20, i * 10 + 10, 30],
          done: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return built;
}
