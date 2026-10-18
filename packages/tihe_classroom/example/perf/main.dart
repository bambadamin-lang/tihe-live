// Frame times, input latency, CPU and memory of the classroom on a real engine, for the
// performance work recorded in docs/11 §11. A plain app (not a test binding, which would draw
// frames continuously and hide idle cost), scripted against the in-process demo server so runs
// repeat exactly and need no network:
//
//   cd packages/tihe_classroom/example
//   flutter build linux --profile -t perf/main.dart
//   xvfb-run -a -s '-screen 0 1920x1080x24' \
//     build/linux/x64/profile/bundle/tihe_classroom_example > perf.log
//
// The last line of the output is `PERF_RESULT {json}`. A software renderer (Xvfb + llvmpipe)
// inflates raster times, so compare runs made on the same machine, never across machines.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

final _window = Duration(
  seconds: int.tryParse(Platform.environment['PERF_SECONDS'] ?? '') ?? 5,
);
const _teacher = DemoClassroom.host;
const _student = DemoClassroom.ali;

final _screen = ValueNotifier<Widget>(const SizedBox());

/// When each synthetic input was dispatched (Timeline clock), to match it to the frame that
/// first showed its effect.
final _inputs = <int>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ValueListenableBuilder<Widget>(
      valueListenable: _screen,
      builder: (_, screen, _) => screen,
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 1));

  final only = Platform.environment['PERF_ONLY'];
  final results = <String, Object?>{};
  Future<void> run(
    String name,
    _Class Function() build,
    Future<void> Function(_Class cls) body,
  ) async {
    if (only != null && !only.split(',').contains(name)) return;
    final cls = build();
    _screen.value = MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: buildClassroomThemeData(ClassroomTheme.dark),
      home: ClassroomPage(session: cls.session, brightness: Brightness.dark),
    );
    // Let the class open and every arrival animation settle before measuring.
    await Future<void>.delayed(const Duration(seconds: 2));
    results[name] = await _measure(() => body(cls));
    _screen.value = const SizedBox();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  await run(
    'idle',
    () => _Class.build(as: _teacher, layout: LayoutPreset.whiteboard),
    (_) => Future<void>.delayed(_window),
  );
  await run(
    'remote_drawing',
    () => _Class.build(as: _student, layout: LayoutPreset.whiteboard),
    (cls) => cls.teacherWrites(_window),
  );
  await run(
    'media_events',
    () => _Class.build(as: _student, layout: LayoutPreset.discussion),
    (cls) => cls.speakersChange(_window),
  );
  await run(
    'local_drawing',
    () => _Class.build(as: _teacher, layout: LayoutPreset.whiteboard),
    (cls) => cls.draw(_window),
  );
  await run(
    'taps_in_busy_class',
    () => _Class.build(as: _student, layout: LayoutPreset.split),
    (cls) => Future.wait([
      cls.teacherWrites(_window),
      cls.speakersChange(_window),
      cls.tapHand(_window),
    ]),
  );
  await run(
    'layout_changes',
    () => _Class.build(as: _student, layout: LayoutPreset.lecture),
    (cls) => cls.cycleLayouts(_window),
  );

  // Memory: open and close the class repeatedly; a leak grows RSS run after run.
  if (only == null || only.split(',').contains('reopen')) {
    final rss = <String>[];
    for (var i = 0; i < 6; i++) {
      final cls = _Class.build(as: _teacher, layout: LayoutPreset.split);
      _screen.value = MaterialApp(
        key: UniqueKey(),
        home: ClassroomPage(session: cls.session, brightness: Brightness.dark),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      _screen.value = const SizedBox();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      rss.add((ProcessInfo.currentRss / (1 << 20)).toStringAsFixed(1));
    }
    results['reopen_rss_mb'] = rss;
  }

  stdout.writeln(
    'PERF_RESULT ${jsonEncode({
      // Impeller or Skia: grouped backdrop blurs share work only under Impeller.
      'impeller': ImageFilter.isShaderFilterSupported,
      'scenarios': results,
    })}',
  );
  await stdout.flush();
  exit(0);
}

/// A demo class with 40 people on camera and 300 strokes on the board.
class _Class {
  _Class._(this.server, this.media, this.session);

  factory _Class.build({required String as, required LayoutPreset layout}) {
    final base = DemoClassroom.snapshot(layout: layoutPresets[layout]);
    final extra = [
      for (var i = 0; i < 32; i++)
        ParticipantState(
          userId: 'usr_01J8ZB${(100 + i).toString().padLeft(20, '0')}',
          name: 'دانشجوی ${i + 1}',
          role: ClassRole.participant,
          caps: const [Capability.chatSend, Capability.handRaise],
          grants: const [],
          revokes: const [],
          hand: null,
          floor: false,
          online: true,
          capturing: false,
          joinedAt: '2026-09-27T06:35:00.000Z',
        ),
    ];
    final snapshot = ClassroomSnapshot(
      sessionId: base.sessionId,
      classId: base.classId,
      title: base.title,
      startedAt: base.startedAt,
      policy: base.policy,
      layout: base.layout,
      participants: [...base.participants, ...extra],
      chat: base.chat,
      board: BoardSnapshot(
        pages: base.board.pages,
        activePageId: base.board.activePageId,
        items: [...base.board.items, ..._strokes(300)],
      ),
      recording: base.recording,
    );
    final server = DemoClassroomServer(snapshot: snapshot)..you = as;
    final everyone = [
      ...DemoClassroom.media(localUserId: as).participants.values,
      for (final p in extra) ParticipantMedia(userId: p.userId, cameraOn: true),
    ];
    final media = FakeClassroomMedia(
      localUserId: as,
      initial: MediaState(
        connected: true,
        activeSpeaker: _teacher,
        participants: {for (final m in everyone) m.userId: m},
      ),
      painter: (userId, slot) => DemoVideo(userId: userId, slot: slot),
    );
    final session = ClassroomSession(
      join: DemoClassroom.join(as: as),
      gateway: GatewayClient(
        url: Uri.parse('ws://demo/v1/live/ws'),
        firstTicket: 'demo-ticket',
        freshTicket: () async => 'demo-ticket',
        connect: server.connect,
      ),
      media: media,
    );
    return _Class._(server, media, session);
  }

  final DemoClassroomServer server;
  final FakeClassroomMedia media;
  final ClassroomSession session;
  int _ids = 0;

  String _id(String prefix) =>
      '${prefix}_01J9PF${(++_ids).toString().padLeft(20, '0')}';

  static List<BoardItem> _strokes(int n) => [
    for (var s = 0; s < n; s++)
      StrokeItem(
        id: 'wbi_01J9PE${s.toString().padLeft(20, '0')}',
        pageId: DemoClassroom.page1,
        color: boardPalette[s % boardPalette.length],
        tool: PenTool.pen,
        width: 24 + s % 3 * 8,
        points: [
          for (var i = 0; i < 60; i++) ...[
            600 + (s % 20) * 740 + i * 9,
            700 + (s ~/ 20) * 520 + ((i * 37 + s * 11) % 160),
          ],
        ],
        by: _teacher,
        seq: 5,
      ),
  ];

  /// The teacher writes: a 40 ms preview batch at a time, a committed stroke every 1.2 s, and
  /// a chat message every second — what a student's app receives in a busy lesson.
  Future<void> teacherWrites(Duration window) async {
    final end = DateTime.now().add(window);
    var nextChat = DateTime.now();
    while (DateTime.now().isBefore(end)) {
      final strokeId = _id('wbi');
      final points = <int>[];
      for (var batch = 0; batch < 30; batch++) {
        final fresh = [
          for (var i = 0; i < 3; i++) ...[
            2000 + (points.length ~/ 2 + i) * 40,
            4500 + ((points.length + i * 13) % 300),
          ],
        ];
        points.addAll(fresh);
        server.relay(
          _teacher,
          BoardProgress(
            strokeId: strokeId,
            pageId: DemoClassroom.page1,
            tool: 'pen',
            color: '#1F4FD8',
            width: 30,
            points: fresh,
            done: batch == 29,
          ),
        );
        if (DateTime.now().isAfter(nextChat)) {
          nextChat = nextChat.add(const Duration(seconds: 1));
          server.emit(
            ChatPosted(
              ChatMessage(
                id: _id('chm'),
                userId: DemoClassroom.sara,
                name: 'سارا محمدی',
                role: ClassRole.participant,
                text: 'پیام آزمایشی برای سنجش کارایی',
                at: DateTime.now().toUtc().toIso8601String(),
              ),
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      server.emit(
        BoardItemsAdded([
          StrokeItem(
            id: strokeId,
            pageId: DemoClassroom.page1,
            color: '#1F4FD8',
            tool: PenTool.pen,
            width: 30,
            points: points,
            by: _teacher,
            seq: server.state.seq + 1,
          ),
        ]),
      );
    }
  }

  /// LiveKit reports who is speaking several times a second in a lively class.
  Future<void> speakersChange(Duration window) async {
    final end = DateTime.now().add(window);
    final ids = media.state.participants.keys.toList();
    var turn = 0;
    while (DateTime.now().isBefore(end)) {
      final speaker = ids[turn++ % ids.length];
      media.emit(
        MediaState(
          connected: true,
          activeSpeaker: speaker,
          participants: {
            for (final m in media.state.participants.values)
              m.userId: ParticipantMedia(
                userId: m.userId,
                micOn: m.micOn || m.userId == speaker,
                cameraOn: m.cameraOn,
                screenOn: m.screenOn,
                speaking: m.userId == speaker,
                isLocal: m.isLocal,
              ),
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Long pen strokes at 120 Hz input, as a tablet pen produces them.
  Future<void> draw(Duration window) async {
    final box = _rectOf((w) => w.runtimeType.toString() == 'BoardCanvas');
    final end = DateTime.now().add(window);
    var stroke = 0;
    while (DateTime.now().isBefore(end)) {
      final y = box.top + box.height * (0.25 + (stroke++ % 5) * 0.12);
      final pointer = _Pointer(Offset(box.left + box.width * 0.15, y));
      for (var i = 0; i < 90; i++) {
        pointer.moveTo(
          Offset(
            box.left + box.width * (0.15 + i * 0.008),
            y + (i % 12 - 6) * 3.0,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
      pointer.up();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  /// A student raises and lowers their hand every 400 ms.
  Future<void> tapHand(Duration window) async {
    final end = DateTime.now().add(window);
    while (DateTime.now().isBefore(end)) {
      final key = _rectOf((w) => w is HandToggle);
      _Pointer(key.center).up();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  Future<void> cycleLayouts(Duration window) async {
    final end = DateTime.now().add(window);
    var i = 0;
    while (DateTime.now().isBefore(end)) {
      final preset = LayoutPreset.values[++i % LayoutPreset.values.length];
      server.emit(LayoutApplied(layoutPresets[preset]!, _teacher));
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
}

/// The on-screen rectangle of the first widget that matches [test].
Rect _rectOf(bool Function(Widget w) test) {
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    if (test(e.widget)) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement!.visitChildren(visit);
  final box = found!.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// A finger on the screen, through the same path real input takes.
class _Pointer {
  _Pointer(this._at) : _id = ++_next {
    _dispatch(
      PointerDownEvent(
        pointer: _id,
        kind: PointerDeviceKind.touch,
        position: _at,
      ),
    );
  }

  static int _next = 100;
  final int _id;
  Offset _at;

  void moveTo(Offset to) {
    final delta = to - _at;
    _at = to;
    _dispatch(
      PointerMoveEvent(
        pointer: _id,
        kind: PointerDeviceKind.touch,
        position: to,
        delta: delta,
      ),
    );
  }

  void up() => _dispatch(
    PointerUpEvent(pointer: _id, kind: PointerDeviceKind.touch, position: _at),
  );

  void _dispatch(PointerEvent e) {
    _inputs.add(Timeline.now);
    GestureBinding.instance.handlePointerEvent(e);
  }
}

/// Frames, frame times, input latency and CPU per thread while [body] runs.
Future<Map<String, Object?>> _measure(Future<void> Function() body) async {
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> t) => timings.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(collect);
  _inputs.clear();
  final cpuBefore = _threadCpu();
  final start = Timeline.now;
  final watch = Stopwatch()..start();
  await body();
  watch.stop();
  final stop = Timeline.now;
  final cpuAfter = _threadCpu();
  // The engine reports frame timings in batches, at least once a second.
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  SchedulerBinding.instance.removeTimingsCallback(collect);

  final inWindow = timings.where((t) {
    final v = t.timestampInMicroseconds(FramePhase.vsyncStart);
    return v >= start && v <= stop;
  }).toList();
  final seconds = watch.elapsedMicroseconds / 1e6;
  double pct(List<double> v, double p) =>
      v.isEmpty ? 0 : v[((v.length - 1) * p).round()];
  double avg(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  List<double> ms(Duration Function(FrameTiming) f) =>
      [for (final t in inWindow) f(t).inMicroseconds / 1000]..sort();
  final build = ms((t) => t.buildDuration);
  final raster = ms((t) => t.rasterDuration);

  // Input latency: from dispatching an input to the end of rasterising the first frame whose
  // build started after it — the earliest frame that can show its effect.
  final latency = <double>[];
  for (final input in _inputs) {
    for (final t in timings) {
      if (t.timestampInMicroseconds(FramePhase.buildStart) >= input) {
        latency.add(
          (t.timestampInMicroseconds(FramePhase.rasterFinish) - input) / 1000,
        );
        break;
      }
    }
  }
  latency.sort();

  const budget = 1000 / 60;
  final cpu = <String, double>{};
  for (final e in cpuAfter.entries) {
    final used = e.value - (cpuBefore[e.key] ?? 0);
    if (used > 0) {
      cpu[e.key] = double.parse((used / seconds * 100).toStringAsFixed(1));
    }
  }
  String r(double v) => v.toStringAsFixed(2);
  return {
    'seconds': r(seconds),
    'frames': inWindow.length,
    'fps': r(inWindow.length / seconds),
    'build_ms_avg': r(avg(build)),
    'build_ms_p90': r(pct(build, 0.9)),
    'build_ms_worst': r(build.isEmpty ? 0 : build.last),
    'raster_ms_avg': r(avg(raster)),
    'raster_ms_p90': r(pct(raster, 0.9)),
    'raster_ms_worst': r(raster.isEmpty ? 0 : raster.last),
    'frames_over_16ms': inWindow
        .where(
          (t) =>
              t.buildDuration.inMicroseconds / 1000 > budget ||
              t.rasterDuration.inMicroseconds / 1000 > budget,
        )
        .length,
    'inputs': _inputs.length,
    'input_latency_ms_avg': r(avg(latency)),
    'input_latency_ms_p90': r(pct(latency, 0.9)),
    'cpu_percent_by_thread': cpu,
    'rss_mb': r(ProcessInfo.currentRss / (1 << 20)),
  };
}

/// CPU seconds used so far by each kind of thread in this process (Linux /proc).
Map<String, double> _threadCpu() {
  final out = <String, double>{};
  final dir = Directory('/proc/self/task');
  if (!dir.existsSync()) return out;
  for (final task in dir.listSync()) {
    try {
      final stat = File('${task.path}/stat').readAsStringSync();
      final open = stat.indexOf('('), close = stat.lastIndexOf(')');
      final name = stat.substring(open + 1, close);
      final fields = stat.substring(close + 2).split(' ');
      // utime and stime: fields 14 and 15 of stat, 11 and 12 after the name.
      final ticks = int.parse(fields[11]) + int.parse(fields[12]);
      // On Linux the UI runs on the main (platform) thread, named after the app. llvmpipe is
      // Mesa's software GPU, standing in for the graphics card under Xvfb.
      final kind = name.startsWith('tihe_classroom')
          ? 'ui'
          : name.contains('raster')
          ? 'raster'
          : name.startsWith('llvmpipe')
          ? 'gpu_sw'
          : name;
      out[kind] = (out[kind] ?? 0) + ticks / 100;
    } on Object {
      // A thread that exited between listing and reading.
    }
  }
  out['total'] = out.values.fold(0, (a, b) => a + b);
  return out;
}
