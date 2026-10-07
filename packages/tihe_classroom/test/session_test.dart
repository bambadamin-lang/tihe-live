import 'dart:async';

import 'package:capture_guard/capture_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

class _Platform implements CaptureGuardPlatform {
  List<String> processes = const [];
  final calls = <String>[];
  @override
  bool get scansProcesses => true;
  @override
  Future<BlockResult> enableBlocking({
    required WindowsAffinity windowsAffinity,
    required bool iosSecureLayer,
  }) async {
    calls.add('block:${windowsAffinity.name}');
    return const BlockResult(
      active: true,
      mechanism: 'wda_monitor',
      failed: false,
    );
  }

  @override
  Future<void> disableBlocking() async => calls.add('unblock');
  @override
  Future<CaptureFacts> readFacts() async => const CaptureFacts();
  @override
  Future<List<String>> runningProcesses() async => processes;
  @override
  Stream<CaptureEvent> get events => const Stream.empty();
}

Future<void> settle([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await settle(10);
  }
  expect(condition(), isTrue);
}

void main() {
  test('joins, receives the class, and follows events', () async {
    final demo = DemoClassroom.build(as: DemoClassroom.ali);
    await demo.session.open();
    await until(() => demo.session.view.value.room != null);
    final view = demo.session.view.value;
    expect(view.role, ClassRole.participant);
    expect(view.gateway, GatewayStatus.online);
    expect(view.room!.layout.id, 'whiteboard');
    expect(view.media.local?.cameraOn, isTrue);
    await demo.session.dispose();
  });

  test(
    'a student lowers their hand; the host gives the floor; the student is told',
    () async {
      final demo = DemoClassroom.build(as: DemoClassroom.ali);
      await demo.session.open();
      await until(() => demo.session.view.value.room != null);

      await demo.session.toggleHand();
      await until(() => demo.session.view.value.me?.hand == null);

      demo.server.you = DemoClassroom.host;
      final ali = demo.server.state.participants[DemoClassroom.ali]!;
      demo.server.emit(
        ParticipantUpdated(
          ParticipantState.fromJson({
            ...ali.toJson(),
            'floor': true,
            'caps': [...ali.toJson()['caps'] as List, 'publish.audio'],
          }),
        ),
      );
      await until(() => demo.session.view.value.can(Capability.publishAudio));
      expect(
        demo.session.view.value.notices.last.textFa,
        contains('اجازهٔ صحبت'),
      );
      await demo.session.dispose();
    },
  );

  test(
    'turns the microphone off when the right to use it is taken away',
    () async {
      final demo = DemoClassroom.build(as: DemoClassroom.sara);
      await demo.session.open();
      await until(() => demo.session.view.value.room != null);
      expect(demo.media.state.local?.micOn, isTrue);

      final sara = demo.server.state.participants[DemoClassroom.sara]!;
      demo.server.emit(
        ParticipantUpdated(
          ParticipantState.fromJson({
            ...sara.toJson(),
            'floor': false,
            'caps': ['chat.send', 'hand.raise'],
          }),
        ),
      );
      await until(() => demo.media.calls.contains('mic:false'));
      await demo.session.dispose();
    },
  );

  test(
    'refuses to unmute without the right, with a hint instead of a silent failure',
    () async {
      final demo = DemoClassroom.build(as: DemoClassroom.ali);
      await demo.session.open();
      await until(() => demo.session.view.value.room != null);
      await demo.session.toggleMicrophone();
      expect(demo.media.calls, isNot(contains('mic:true')));
      expect(
        demo.session.view.value.notices.last.textFa,
        contains('دست خود را بالا ببرید'),
      );
      await demo.session.dispose();
    },
  );

  test('shows a refusal in the server\'s own Persian words', () async {
    final demo = DemoClassroom.build(as: DemoClassroom.ali);
    await demo.session.open();
    await until(() => demo.session.view.value.room != null);
    final outcome = await demo.session.send(
      ApplyLayout(layoutPresets[LayoutPreset.qa]!),
    );
    expect(outcome, isA<Refused>());
    expect(
      demo.session.view.value.notices.last.textFa,
      'در این کلاس اجازهٔ انجام این کار را ندارید.',
    );
    await demo.session.dispose();
  });

  test(
    'censors the class, mutes it, and tells the host when a recorder starts',
    () async {
      final platform = _Platform();
      final demo = DemoClassroom.build(
        as: DemoClassroom.ali,
        capture: CaptureMonitor(
          platform: platform,
          // Short grace period: the real one (2 s) would make this test slow.
          engine: CapturePolicyEngine(
            recorderProcesses: ['obs64.exe'],
            clearAfter: const Duration(milliseconds: 100),
          ),
          block: true,
          windowsAffinity: WindowsAffinity.monitor,
          iosSecureLayer: false,
          scanInterval: const Duration(milliseconds: 50),
        ),
      );
      await demo.session.open();
      await until(() => demo.session.view.value.room != null);
      expect(platform.calls.first, 'block:monitor');
      expect(demo.session.view.value.capture.censor, isFalse);

      platform.processes = ['obs64.exe'];
      await until(() => demo.session.view.value.capture.censor);
      expect(demo.media.remoteAudioMuted, isTrue);
      await until(
        () => demo.server.received.any(
          (m) =>
              m['t'] == 'cmd' && (m['cmd'] as Map)['type'] == 'capture.report',
        ),
      );
      final report =
          demo.server.received.lastWhere((m) => m['t'] == 'cmd')['cmd'] as Map;
      expect(report['capturing'], isTrue);
      expect(report['detail'], 'obs64.exe');

      platform.processes = [];
      await until(() => !demo.session.view.value.capture.censor);
      expect(demo.media.remoteAudioMuted, isFalse);
      await demo.session.dispose();
      expect(platform.calls.last, 'unblock');
    },
  );

  group('a recording that is not stopped', () {
    ({ClassroomSession session, DemoClassroomServer server, _Platform platform})
    build(int? grace) {
      final platform = _Platform();
      final demo = DemoClassroom.build(
        as: DemoClassroom.ali,
        recordingGraceSeconds: grace,
        capture: CaptureMonitor(
          platform: platform,
          engine: CapturePolicyEngine(
            recorderProcesses: ['obs64.exe'],
            clearAfter: const Duration(milliseconds: 100),
          ),
          block: true,
          windowsAffinity: WindowsAffinity.monitor,
          iosSecureLayer: false,
          scanInterval: const Duration(milliseconds: 50),
        ),
      );
      return (session: demo.session, server: demo.server, platform: platform);
    }

    test(
      'takes the student out after the grace period, and tells the host',
      () async {
        final c = build(1);
        await c.session.open();
        await until(() => c.session.view.value.room != null);
        c.platform.processes = ['obs64.exe'];
        await until(() => c.session.view.value.capture.censor);
        expect(c.session.recordingDeadline, isNotNull);
        expect(c.session.view.value.exit, isNull);

        await until(() => c.session.view.value.exit != null);
        expect(c.session.view.value.exit, ClassroomExit.removedForRecording);
        final last =
            c.server.received.lastWhere((m) => m['t'] == 'cmd')['cmd'] as Map;
        expect(last['type'], 'capture.report');
        expect(last['signals'], contains('removed_for_recording'));
        await c.session.dispose();
      },
    );

    test('closing the recorder in time cancels it', () async {
      final c = build(1);
      await c.session.open();
      await until(() => c.session.view.value.room != null);
      c.platform.processes = ['obs64.exe'];
      await until(() => c.session.view.value.capture.censor);
      c.platform.processes = [];
      await until(() => !c.session.view.value.capture.censor);
      expect(c.session.recordingDeadline, isNull);
      await settle(1300);
      expect(c.session.view.value.exit, isNull);
      await c.session.dispose();
    });

    test('never removes anyone where the course allows capture', () async {
      final c = build(null);
      await c.session.open();
      await until(() => c.session.view.value.room != null);
      c.platform.processes = ['obs64.exe'];
      await until(() => c.session.view.value.capture.censor);
      expect(c.session.recordingDeadline, isNull);
      await c.session.dispose();
    });
  });

  test(
    'a presenter is excluded from captures rather than shown as a black box',
    () async {
      final platform = _Platform();
      final demo = DemoClassroom.build(
        as: DemoClassroom.ali,
        capture: CaptureMonitor(
          platform: platform,
          engine: CapturePolicyEngine(recorderProcesses: const []),
          block: true,
          windowsAffinity: WindowsAffinity.monitor,
          iosSecureLayer: false,
        ),
      );
      await demo.session.open();
      await until(() => demo.session.view.value.room != null);
      final ali = demo.server.state.participants[DemoClassroom.ali]!;
      demo.server.emit(
        ParticipantUpdated(
          ParticipantState.fromJson({...ali.toJson(), 'role': 'presenter'}),
        ),
      );
      await until(() => platform.calls.contains('block:exclude'));
      await demo.session.dispose();
    },
  );

  test(
    'draws a stroke: preview while drawing, committed on pen-up, undo removes it',
    () async {
      final demo = DemoClassroom.build(as: DemoClassroom.host);
      await demo.session.open();
      await until(() => demo.session.view.value.room != null);
      final board = demo.session.board;
      final room = demo.session.view.value.room!;
      final before = room.items.length;

      board.selectTool(BoardTool.marker);
      board.pointerDown((x: 1000, y: 1000), room, canManage: true);
      for (var i = 1; i <= 20; i++) {
        board.pointerMove((x: 1000 + i * 100, y: 1000 + i * 30), room);
      }
      await settle(60);
      await board.pointerUp();
      await until(
        () => demo.session.view.value.room!.items.length == before + 1,
      );
      expect(board.pending, isEmpty);
      final added = demo.server.received.where(
        (m) => m['t'] == 'cmd' && (m['cmd'] as Map)['type'] == 'wb.add',
      );
      expect(added, hasLength(1));

      await board.undo();
      await until(() => demo.session.view.value.room!.items.length == before);
      await demo.session.dispose();
    },
  );

  test('leaves when the class ends', () async {
    final demo = DemoClassroom.build(as: DemoClassroom.ali);
    await demo.session.open();
    await until(() => demo.session.view.value.room != null);
    demo.server.emit(const ClassEnded('host_ended'));
    await until(() => demo.session.view.value.exit == ClassroomExit.ended);
    await demo.session.dispose();
  });
}
