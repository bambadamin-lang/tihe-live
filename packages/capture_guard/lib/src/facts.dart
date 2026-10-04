import 'package:flutter/foundation.dart';

/// Why a class may be censored. Wire names match `CAPTURE_SIGNALS` in
/// packages/contracts/src/live/capture.ts, which is what the gateway receives.
enum CaptureSignal {
  /// The OS says this app is being recorded (Android 15 callback, iOS capture state).
  osRecording('os_recording'),

  /// A screenshot was taken — an instant, not a state.
  screenshot('screenshot'),

  /// A known screen-recorder process is running (Windows, macOS).
  recorderProcess('recorder_process'),

  /// The screen is mirrored or sent to another display (AirPlay, Miracast).
  externalDisplay('external_display'),

  /// Running inside a Remote Desktop session, which can itself be recorded.
  remoteSession('remote_session'),

  /// The OS refused to block capture.
  blockFailed('block_failed'),

  /// The recording outlasted the grace period and the app left the class. Sent once, as it goes.
  removedForRecording('removed_for_recording');

  const CaptureSignal(this.wire);
  final String wire;
}

/// Windows display affinity (ADR-0011). `monitor`: captures show a black box — for students,
/// so the censorship is visible. `exclude`: the window vanishes from captures — for presenters,
/// so their own screen share has no black hole in it.
enum WindowsAffinity { monitor, exclude }

/// What the native side can observe right now. Facts only; [CapturePolicyEngine] decides.
@immutable
class CaptureFacts {
  const CaptureFacts({
    this.osRecording = false,
    this.externalDisplay = false,
    this.remoteSession = false,
    this.runningProcesses = const [],
  });

  factory CaptureFacts.fromMap(Map<Object?, Object?> map) => CaptureFacts(
    osRecording: map['osRecording'] == true,
    externalDisplay: map['externalDisplay'] == true,
    remoteSession: map['remoteSession'] == true,
  );

  final bool osRecording;
  final bool externalDisplay;
  final bool remoteSession;

  /// Lower-case executable or app names (desktop only; empty elsewhere).
  final List<String> runningProcesses;

  CaptureFacts withProcesses(List<String> processes) => CaptureFacts(
    osRecording: osRecording,
    externalDisplay: externalDisplay,
    remoteSession: remoteSession,
    runningProcesses: processes,
  );

  @override
  bool operator ==(Object other) =>
      other is CaptureFacts &&
      other.osRecording == osRecording &&
      other.externalDisplay == externalDisplay &&
      other.remoteSession == remoteSession &&
      listEquals(other.runningProcesses, runningProcesses);

  @override
  int get hashCode => Object.hash(
    osRecording,
    externalDisplay,
    remoteSession,
    Object.hashAll(runningProcesses),
  );
}

/// The outcome of asking the OS to block capture.
@immutable
class BlockResult {
  const BlockResult({
    required this.active,
    required this.mechanism,
    required this.failed,
  });

  factory BlockResult.fromMap(Map<Object?, Object?> map) => BlockResult(
    active: map['active'] == true,
    mechanism: (map['mechanism'] as String?) ?? 'none',
    failed: map['failed'] == true,
  );

  /// Nothing to block with on this platform (Linux development builds).
  static const unsupported = BlockResult(
    active: false,
    mechanism: 'none',
    failed: false,
  );

  final bool active;

  /// `wda_monitor`, `wda_exclude`, `flag_secure`, `sharing_none`, `secure_layer` or `none`.
  final String mechanism;

  /// Blocking was requested and the OS refused it.
  final bool failed;
}
