import 'dart:async';

import 'package:flutter/foundation.dart';

import 'facts.dart';
import 'platform.dart';
import 'policy.dart';

/// What the classroom tells the gateway (`capture.report`). Sent when the censor state
/// changes, and once per screenshot.
@immutable
class CaptureReport {
  const CaptureReport({
    required this.capturing,
    required this.signals,
    this.detail,
  });

  final bool capturing;
  final List<CaptureSignal> signals;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is CaptureReport &&
      other.capturing == capturing &&
      listEquals(other.signals, signals) &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(capturing, Object.hashAll(signals), detail);
}

/// Ties the native side to the policy: blocks capture, polls and listens for facts, and emits
/// verdicts for the UI and reports for the host.
class CaptureMonitor {
  CaptureMonitor({
    required CaptureGuardPlatform platform,
    required CapturePolicyEngine engine,
    required this.block,
    required this.windowsAffinity,
    required this.iosSecureLayer,
    this.scanInterval = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _platform = platform,
       _engine = engine,
       _clock = clock ?? DateTime.now;

  final CaptureGuardPlatform _platform;
  final CapturePolicyEngine _engine;
  final DateTime Function() _clock;

  /// False only for courses with `allowCapture` (docs/03): detection still runs.
  final bool block;
  WindowsAffinity windowsAffinity;
  final bool iosSecureLayer;
  final Duration scanInterval;

  final _verdicts = StreamController<CaptureVerdict>.broadcast();
  final _reports = StreamController<CaptureReport>.broadcast();
  StreamSubscription<CaptureEvent>? _events;
  Timer? _timer;
  CaptureFacts _facts = const CaptureFacts();
  CaptureVerdict _verdict = CaptureVerdict.clear;
  BlockResult _blockResult = BlockResult.unsupported;
  bool _ownShareActive = false;
  bool _reportedBlockFailure = false;

  Stream<CaptureVerdict> get verdicts => _verdicts.stream;
  Stream<CaptureReport> get reports => _reports.stream;
  CaptureVerdict get verdict => _verdict;
  BlockResult get blockResult => _blockResult;

  /// The presenter's own screen share is running: do not treat it as a recording.
  set ownShareActive(bool value) {
    if (_ownShareActive == value) return;
    _ownShareActive = value;
    _reevaluate();
  }

  Future<void> start() async {
    if (block) {
      _blockResult = await _platform.enableBlocking(
        windowsAffinity: windowsAffinity,
        iosSecureLayer: iosSecureLayer,
      );
    }
    _events = _platform.events.listen((event) {
      switch (event) {
        case FactsChanged(:final facts):
          _facts = facts.withProcesses(_facts.runningProcesses);
          _reevaluate();
        case ScreenshotTaken():
          _reports.add(
            CaptureReport(
              capturing: _verdict.censor,
              signals: const [CaptureSignal.screenshot],
            ),
          );
      }
    });
    await poll();
    _timer = Timer.periodic(scanInterval, (_) => poll());
  }

  /// Reads the facts once. Called on a timer; public so tests can drive it.
  Future<void> poll() async {
    final facts = await _platform.readFacts();
    final processes = _platform.scansProcesses
        ? await _platform.runningProcesses()
        : const <String>[];
    _facts = facts.withProcesses(processes);
    _reevaluate();
  }

  /// The role changed mid-class (promoted to presenter, or back): re-apply the right affinity.
  Future<void> setWindowsAffinity(WindowsAffinity affinity) async {
    if (affinity == windowsAffinity) return;
    windowsAffinity = affinity;
    if (block) {
      _blockResult = await _platform.enableBlocking(
        windowsAffinity: affinity,
        iosSecureLayer: iosSecureLayer,
      );
    }
  }

  void _reevaluate() {
    final next = _engine.evaluate(
      _facts,
      now: _clock(),
      ownShareActive: _ownShareActive,
      blockFailed: _blockResult.failed,
    );
    final previous = _verdict;
    _verdict = next;
    if (next != previous) _verdicts.add(next);

    final signalsChanged = !setEquals(
      next.signals.toSet(),
      previous.signals.toSet(),
    );
    if (next.censor != previous.censor || (next.censor && signalsChanged)) {
      _reports.add(
        CaptureReport(
          capturing: next.censor,
          signals: next.signals,
          detail: next.detail,
        ),
      );
    } else if (_blockResult.failed && !_reportedBlockFailure) {
      _reports.add(
        const CaptureReport(
          capturing: false,
          signals: [CaptureSignal.blockFailed],
        ),
      );
    }
    if (_blockResult.failed) _reportedBlockFailure = true;
  }

  Future<void> dispose() async {
    _timer?.cancel();
    final cancelled = _events?.cancel();
    if (block) await _platform.disableBlocking();
    await cancelled;
    await _verdicts.close();
    await _reports.close();
  }
}
