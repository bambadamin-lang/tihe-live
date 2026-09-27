import 'package:flutter/foundation.dart';

import 'facts.dart';

/// What the classroom does about the current facts.
@immutable
class CaptureVerdict {
  const CaptureVerdict({
    required this.censor,
    required this.signals,
    this.detail,
  });

  static const clear = CaptureVerdict(censor: false, signals: []);

  /// Replace the class with the censor screen and mute remote audio.
  final bool censor;
  final List<CaptureSignal> signals;

  /// For the host's alert: which recorder, for instance.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is CaptureVerdict &&
      other.censor == censor &&
      listEquals(other.signals, signals) &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(censor, Object.hashAll(signals), detail);
}

/// ADR-0011, as code: native code reports facts, this decides. Pure, so every rule is tested on
/// any machine.
///
/// - A known recorder process, OS-reported recording, a mirrored display or a Remote Desktop
///   session censors the class.
/// - The presenter's own screen share uses the same OS machinery (MediaProjection, ReplayKit),
///   so OS-reported recording is ignored while their own share runs — but a mirrored display
///   still counts, because AirPlay mirroring also looks like "captured" on iOS.
/// - A refused block is reported, not censored: the class would be unusable, and the host
///   decides.
/// - Censoring lifts only after the facts have been clear for [clearAfter], so a recorder that
///   flickers on and off cannot slip frames through the gaps.
class CapturePolicyEngine {
  CapturePolicyEngine({
    required Iterable<String> recorderProcesses,
    this.clearAfter = const Duration(seconds: 2),
  }) : _recorders = {for (final n in recorderProcesses) n.toLowerCase()};

  final Set<String> _recorders;
  final Duration clearAfter;
  DateTime? _lastCaptured;

  CaptureVerdict evaluate(
    CaptureFacts facts, {
    required DateTime now,
    bool ownShareActive = false,
    bool blockFailed = false,
  }) {
    final signals = <CaptureSignal>[];
    final recorders = [
      for (final p in facts.runningProcesses)
        if (_recorders.contains(p.toLowerCase())) p,
    ];
    if (recorders.isNotEmpty) signals.add(CaptureSignal.recorderProcess);
    if (facts.osRecording && !ownShareActive) {
      signals.add(CaptureSignal.osRecording);
    }
    if (facts.externalDisplay) signals.add(CaptureSignal.externalDisplay);
    if (facts.remoteSession) signals.add(CaptureSignal.remoteSession);

    final capturingNow = signals.isNotEmpty;
    if (blockFailed) signals.add(CaptureSignal.blockFailed);
    if (capturingNow) _lastCaptured = now;

    final last = _lastCaptured;
    final censor =
        capturingNow || (last != null && now.difference(last) < clearAfter);
    return CaptureVerdict(
      censor: censor,
      signals: signals,
      detail: recorders.isEmpty ? null : recorders.toSet().join(', '),
    );
  }
}
