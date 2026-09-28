import 'dart:async';

import 'package:capture_guard/capture_guard.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform implements CaptureGuardPlatform {
  FakePlatform({
    this.blockResult = const BlockResult(
      active: true,
      mechanism: 'wda_monitor',
      failed: false,
    ),
  });

  final BlockResult blockResult;
  CaptureFacts facts = const CaptureFacts();
  List<String> processes = const [];
  final events$ = StreamController<CaptureEvent>.broadcast();
  final calls = <String>[];

  @override
  bool get scansProcesses => true;

  @override
  Future<BlockResult> enableBlocking({
    required WindowsAffinity windowsAffinity,
    required bool iosSecureLayer,
  }) async {
    calls.add('enable:${windowsAffinity.name}');
    return blockResult;
  }

  @override
  Future<void> disableBlocking() async => calls.add('disable');

  @override
  Future<CaptureFacts> readFacts() async => facts;

  @override
  Future<List<String>> runningProcesses() async => processes;

  @override
  Stream<CaptureEvent> get events => events$.stream;
}

void main() {
  late FakePlatform platform;
  late CaptureMonitor monitor;
  late List<CaptureReport> reports;
  late DateTime now;

  CaptureMonitor build({bool block = true}) => CaptureMonitor(
    platform: platform,
    engine: CapturePolicyEngine(recorderProcesses: ['obs64.exe']),
    block: block,
    windowsAffinity: WindowsAffinity.monitor,
    iosSecureLayer: true,
    clock: () => now,
  );

  // Fakes are built inside the fake zone, so their stream futures run on its clock.
  void run(void Function(FakeAsync async) body) => fakeAsync((async) {
    platform = FakePlatform();
    now = DateTime.utc(2026, 9, 27, 8);
    reports = [];
    body(async);
  });

  test('blocks on start and unblocks on dispose', () {
    run((async) {
      monitor = build()..start();
      async.flushMicrotasks();
      expect(platform.calls, ['enable:monitor']);
      monitor.dispose();
      async.flushMicrotasks();
      expect(platform.calls.last, 'disable');
    });
  });

  test('does not block when the course allows capture, but still detects', () {
    run((async) {
      platform.processes = ['obs64.exe'];
      monitor = build(block: false)..start();
      async.flushMicrotasks();
      expect(platform.calls, isEmpty);
      expect(monitor.verdict.censor, isTrue);
      monitor.dispose();
    });
  });

  test(
    'a recorder started mid-class is found by the next scan and reported once',
    () {
      run((async) {
        monitor = build();
        monitor.reports.listen(reports.add);
        monitor.start();
        async.flushMicrotasks();
        expect(reports, isEmpty);

        platform.processes = ['obs64.exe'];
        async.elapse(const Duration(seconds: 3));
        expect(monitor.verdict.censor, isTrue);
        expect(reports, [
          const CaptureReport(
            capturing: true,
            signals: [CaptureSignal.recorderProcess],
            detail: 'obs64.exe',
          ),
        ]);

        async.elapse(const Duration(seconds: 3));
        expect(reports, hasLength(1));

        platform.processes = [];
        now = now.add(const Duration(seconds: 10));
        async.elapse(const Duration(seconds: 3));
        expect(monitor.verdict.censor, isFalse);
        expect(reports.last.capturing, isFalse);
        monitor.dispose();
      });
    },
  );

  test(
    'pushed OS facts act immediately, and the own share suppresses them',
    () {
      run((async) {
        monitor = build();
        monitor.start();
        async.flushMicrotasks();
        monitor.ownShareActive = true;
        platform.events$.add(
          const FactsChanged(CaptureFacts(osRecording: true)),
        );
        async.flushMicrotasks();
        expect(monitor.verdict.censor, isFalse);
        monitor.ownShareActive = false;
        expect(monitor.verdict.censor, isTrue);
        monitor.dispose();
      });
    },
  );

  test('a screenshot is reported as an instant', () {
    run((async) {
      monitor = build();
      monitor.reports.listen(reports.add);
      monitor.start();
      async.flushMicrotasks();
      platform.events$.add(const ScreenshotTaken());
      async.flushMicrotasks();
      expect(reports.single.signals, [CaptureSignal.screenshot]);
      expect(reports.single.capturing, isFalse);
      monitor.dispose();
    });
  });

  test('a refused block is reported to the host once', () {
    run((async) {
      platform = FakePlatform(
        blockResult: const BlockResult(
          active: false,
          mechanism: 'none',
          failed: true,
        ),
      );
      monitor = build();
      monitor.reports.listen(reports.add);
      monitor.start();
      async.elapse(const Duration(seconds: 7));
      expect(reports.single.signals, [CaptureSignal.blockFailed]);
      expect(monitor.verdict.censor, isFalse);
      monitor.dispose();
    });
  });

  test('a promotion to presenter re-applies the Windows affinity', () {
    run((async) {
      monitor = build();
      monitor.start();
      async.flushMicrotasks();
      monitor.setWindowsAffinity(WindowsAffinity.exclude);
      async.flushMicrotasks();
      expect(platform.calls, ['enable:monitor', 'enable:exclude']);
      monitor.dispose();
    });
  });
}
