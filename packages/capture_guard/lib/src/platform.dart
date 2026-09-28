import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'facts.dart';

/// Something the native side pushes without being asked.
sealed class CaptureEvent {
  const CaptureEvent();
}

class FactsChanged extends CaptureEvent {
  const FactsChanged(this.facts);
  final CaptureFacts facts;
}

class ScreenshotTaken extends CaptureEvent {
  const ScreenshotTaken();
}

/// The native half of capture_guard. An interface so the policy and monitor are tested with a
/// fake, and so Linux development builds run with no native code at all.
abstract class CaptureGuardPlatform {
  Future<BlockResult> enableBlocking({
    required WindowsAffinity windowsAffinity,
    required bool iosSecureLayer,
  });

  Future<void> disableBlocking();

  /// OS capture state, mirrors and remote sessions. Never includes processes.
  Future<CaptureFacts> readFacts();

  /// Lower-case names of running processes (Windows, macOS); empty elsewhere.
  Future<List<String>> runningProcesses();

  Stream<CaptureEvent> get events;

  /// Whether this platform scans processes (desktop) — the monitor only polls where it helps.
  bool get scansProcesses;
}

class MethodChannelCaptureGuard implements CaptureGuardPlatform {
  MethodChannelCaptureGuard();

  static const _methods = MethodChannel('tihe/capture_guard');
  static const _events = EventChannel('tihe/capture_guard/events');

  bool get _native =>
      !kIsWeb &&
      (Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isAndroid ||
          Platform.isIOS);

  @override
  bool get scansProcesses =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS);

  @override
  Future<BlockResult> enableBlocking({
    required WindowsAffinity windowsAffinity,
    required bool iosSecureLayer,
  }) async {
    if (!_native) return BlockResult.unsupported;
    final map = await _methods.invokeMapMethod<Object?, Object?>(
      'enableBlocking',
      {
        'windowsAffinity': windowsAffinity.name,
        'iosSecureLayer': iosSecureLayer,
      },
    );
    return map == null ? BlockResult.unsupported : BlockResult.fromMap(map);
  }

  @override
  Future<void> disableBlocking() async {
    if (_native) await _methods.invokeMethod<void>('disableBlocking');
  }

  @override
  Future<CaptureFacts> readFacts() async {
    if (!_native) return const CaptureFacts();
    final map = await _methods.invokeMapMethod<Object?, Object?>('readFacts');
    return map == null ? const CaptureFacts() : CaptureFacts.fromMap(map);
  }

  @override
  Future<List<String>> runningProcesses() async {
    if (!scansProcesses) return const [];
    final list = await _methods.invokeListMethod<String>('runningProcesses');
    return [for (final name in list ?? const <String>[]) name.toLowerCase()];
  }

  @override
  Stream<CaptureEvent> get events {
    // Windows has nothing to push; the monitor polls it instead.
    if (!_native || Platform.isWindows) return const Stream.empty();
    return _events.receiveBroadcastStream().map((raw) {
      final map = raw as Map<Object?, Object?>;
      return map['event'] == 'screenshot'
          ? const ScreenshotTaken()
          : FactsChanged(CaptureFacts.fromMap(map));
    });
  }
}
