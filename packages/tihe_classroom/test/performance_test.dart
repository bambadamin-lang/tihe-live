import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// How much of the classroom rebuilds per real-time event.
///
/// A class is a stream of small events — a few points of someone's stroke, a speaking indicator
/// moving, a chat message — dozens a second. Each should rebuild the few widgets that show it, not
/// the stage. These counts are deterministic, so a regression shows up here long before it shows
/// up as a laggy class.
void main() {
  late Map<String, int> rebuilt;

  setUp(() {
    rebuilt = {};
    widgets.debugOnRebuildDirtyWidget = (element, builtOnce) {
      final name = element.widget.runtimeType.toString();
      rebuilt[name] = (rebuilt[name] ?? 0) + 1;
    };
  });
  tearDown(() => widgets.debugOnRebuildDirtyWidget = null);

  Future<({DemoClassroomServer server, FakeClassroomMedia media})> open(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final demo = DemoClassroom.build(as: DemoClassroom.host);
    await tester.pumpWidget(
      MaterialApp(home: ClassroomPage(session: demo.session)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
    return (server: demo.server, media: demo.media);
  }

  int total() => rebuilt.values.fold(0, (a, b) => a + b);

  /// Rebuilt at least once since the last clear.
  bool touched(String widget) => (rebuilt[widget] ?? 0) > 0;

  void report(String label, int events) {
    final top = rebuilt.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // ignore: avoid_print
    print(
      '$label: ${total()} rebuilds for $events events '
      '(${(total() / events).toStringAsFixed(1)}/event); top: '
      '${top.take(8).map((e) => '${e.key}×${e.value}').join(', ')}',
    );
  }

  testWidgets('remote whiteboard strokes', (tester) async {
    final c = await open(tester);
    rebuilt.clear();
    for (var i = 0; i < 30; i++) {
      c.server.relay(
        DemoClassroom.cohost,
        BoardProgress(
          strokeId: 'wbi_perf_1',
          pageId: DemoClassroom.page1,
          tool: 'pen',
          color: '#1D4ED8',
          width: 28,
          points: [100 + i * 10, 200 + i * 5],
          done: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 33));
    }
    report('strokes', 30);
    // Only the board has anything new to show.
    expect(touched('BoardCanvas'), isTrue);
    for (final w in ['ControlBar', 'SpeakerPod', 'ChatPod', 'MarkerTray']) {
      expect(touched(w), isFalse, reason: '$w rebuilt for a remote stroke');
    }
    expect(total() / 30, lessThan(15));
  });

  testWidgets('media updates that change nothing', (tester) async {
    final c = await open(tester);
    final state = DemoClassroom.media(localUserId: DemoClassroom.host);
    rebuilt.clear();
    for (var i = 0; i < 20; i++) {
      // A fresh but equal value, as LiveKit's room events produce.
      c.media.emit(
        MediaState(
          connected: state.connected,
          activeSpeaker: state.activeSpeaker,
          participants: {...state.participants},
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    report('unchanged media', 20);
    for (final w in ['ControlBar', 'SpeakerPod', 'BoardCanvas', 'ChatPod']) {
      expect(touched(w), isFalse, reason: '$w rebuilt for an unchanged update');
    }
    // What remains is the recording lamp's own pulse, not the updates.
    expect(total() / 20, lessThan(6));
  });

  testWidgets('the speaking indicator moving', (tester) async {
    final c = await open(tester);
    final state = DemoClassroom.media(localUserId: DemoClassroom.host);
    rebuilt.clear();
    for (var i = 0; i < 10; i++) {
      final speaker = i.isEven ? DemoClassroom.sara : DemoClassroom.host;
      c.media.emit(
        MediaState(
          connected: true,
          activeSpeaker: speaker,
          participants: {
            for (final e in state.participants.entries)
              e.key: ParticipantMedia(
                userId: e.value.userId,
                micOn: e.value.micOn,
                cameraOn: e.value.cameraOn,
                screenOn: e.value.screenOn,
                speaking: e.key == speaker,
                isLocal: e.value.isLocal,
              ),
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    report('speaking', 10);
    for (final w in ['ControlBar', 'BoardCanvas', 'ChatPod', 'MarkerTray']) {
      expect(touched(w), isFalse, reason: '$w rebuilt for a speaking change');
    }
    expect(total() / 10, lessThan(30));
  });

  testWidgets('a chat message', (tester) async {
    final c = await open(tester);
    rebuilt.clear();
    for (var i = 0; i < 5; i++) {
      c.server.emit(
        ChatPosted(
          ChatMessage(
            id: 'chm_perf_$i',
            userId: DemoClassroom.ali,
            name: 'علی کریمی',
            role: ClassRole.participant,
            text: 'پیام $i',
            at: DateTime.utc(2026, 9, 28, 10, i).toIso8601String(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    report('chat', 5);
    for (final w in ['ControlBar', 'BoardCanvas', 'SpeakerPod', 'MarkerTray']) {
      expect(touched(w), isFalse, reason: '$w rebuilt for a chat message');
    }
    expect(total() / 5, lessThan(140));
  });

  testWidgets('the canvas survives a window dragged through many shapes', (
    tester,
  ) async {
    // Its glows are baked into a few cached images and the oldest are released; a released image
    // drawn again would throw here.
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final brightness in Brightness.values) {
      for (var w = 600.0; w <= 2400; w += 150) {
        tester.view.physicalSize = Size(w, 800);
        await tester.pumpWidget(
          Theme(
            data: buildClassroomThemeData(
              ClassroomTheme.forBrightness(brightness),
            ),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: GlassBackdrop(child: SizedBox.expand()),
            ),
          ),
        );
      }
    }
    tester.view.physicalSize = const Size(600, 800);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
