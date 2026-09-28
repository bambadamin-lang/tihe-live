import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// Frame timings for the classroom under realistic load, in profile mode:
///
///   xvfb-run -s "-screen 0 1600x1000x24" flutter drive --profile -d linux \
///     --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
///
/// Each scenario writes `build/perf/NAME.timeline_summary.json` (frame count, build and raster
/// times). The demo class is static, so the load is scripted here: webcams that change every
/// frame like real video, remote whiteboard strokes, and speaking indicators flickering.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('classroom under load', (tester) async {
    final server = DemoClassroomServer(snapshot: DemoClassroom.snapshot())
      ..you = DemoClassroom.host;
    var mediaState = DemoClassroom.media(localUserId: DemoClassroom.host);
    final media = FakeClassroomMedia(
      localUserId: DemoClassroom.host,
      initial: mediaState,
      painter: (userId, slot) => _LiveVideo(seed: userId.hashCode),
    );
    final session = ClassroomSession(
      join: DemoClassroom.join(as: DemoClassroom.host),
      gateway: GatewayClient(
        url: Uri.parse('ws://demo/v1/live/ws'),
        firstTicket: 'demo-ticket',
        freshTicket: () async => 'demo-ticket',
        connect: server.connect,
      ),
      media: media,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ClassroomPage(session: session, brightness: Brightness.dark),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));

    // 1. Nobody touches anything: a live class with its clock, recording lamp and webcams.
    await binding.traceAction(
      () => Future<void>.delayed(const Duration(seconds: 5)),
      reportKey: 'idle',
    );

    // 2. Real-time traffic: someone draws on the board (30 progress messages a second) while
    //    the speaking indicator moves between two people four times a second.
    await binding.traceAction(() async {
      final stop = DateTime.now().add(const Duration(seconds: 5));
      var tick = 0;
      final points = <int>[];
      while (DateTime.now().isBefore(stop)) {
        tick++;
        final t = tick / 8;
        final chunk = [
          (800 + 400 * cos(t)).round(),
          (500 + 250 * sin(t * 1.3)).round(),
        ];
        points.addAll(chunk);
        server.relay(
          DemoClassroom.cohost,
          BoardProgress(
            strokeId: 'wbi_perf_${tick ~/ 90}',
            pageId: DemoClassroom.page1,
            tool: 'pen',
            color: '#1D4ED8',
            width: 28,
            points: chunk,
            done: false,
          ),
        );
        if (tick % 8 == 0) {
          final speaker = (tick ~/ 8).isEven
              ? DemoClassroom.host
              : DemoClassroom.sara;
          mediaState = MediaState(
            connected: true,
            activeSpeaker: speaker,
            participants: {
              for (final e in mediaState.participants.entries)
                e.key: ParticipantMedia(
                  userId: e.value.userId,
                  micOn: e.value.micOn,
                  cameraOn: e.value.cameraOn,
                  screenOn: e.value.screenOn,
                  speaking: e.key == speaker,
                  isLocal: e.value.isLocal,
                ),
            },
          );
          media.emit(mediaState);
        }
        // Unchanged state, re-sent: LiveKit reports every room event, not only changes.
        if (tick % 3 == 0) media.emit(mediaState);
        await Future<void>.delayed(const Duration(milliseconds: 33));
      }
    }, reportKey: 'traffic');

    // 3. The user works the controls.
    await binding.traceAction(() async {
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byTooltip('میکروفون'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('چیدمان'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.tap(find.byTooltip('بستن'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await tester.tap(find.byTooltip('پوستهٔ روشن'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.tap(find.byTooltip('پوستهٔ تیره'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }, reportKey: 'interactions');

    // 4. Discussion: eight webcams in the gallery, all live.
    server.emit(
      LayoutApplied(
        layoutPresets[LayoutPreset.discussion]!,
        DemoClassroom.host,
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    await binding.traceAction(
      () => Future<void>.delayed(const Duration(seconds: 5)),
      reportKey: 'gallery',
    );

    await tester.pumpWidget(const SizedBox());
    await session.dispose();
  });
}

/// A stand-in for a webcam that, like a real video texture, changes every frame.
class _LiveVideo extends StatefulWidget {
  const _LiveVideo({required this.seed});

  final int seed;

  @override
  State<_LiveVideo> createState() => _LiveVideoState();
}

class _LiveVideoState extends State<_LiveVideo>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _Frame(_controller, widget.seed),
      size: Size.infinite,
    ),
  );
}

class _Frame extends CustomPainter {
  _Frame(this.progress, this.seed) : super(repaint: progress);

  final Animation<double> progress;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final hue = (seed % 360 + progress.value * 40) % 360;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = HSLColor.fromAHSL(1, hue, 0.3, 0.3).toColor(),
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height * (0.45 + 0.03 * progress.value)),
      size.shortestSide * 0.25,
      Paint()..color = const Color(0x55000000),
    );
  }

  @override
  bool shouldRepaint(_Frame old) => false;
}
