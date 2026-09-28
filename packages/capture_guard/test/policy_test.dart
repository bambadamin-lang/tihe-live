import 'package:capture_guard/capture_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 27, 8);
  CapturePolicyEngine engine() =>
      CapturePolicyEngine(recorderProcesses: ['obs64.exe', 'Loom']);

  test('clear facts, clear verdict', () {
    expect(
      engine().evaluate(const CaptureFacts(), now: t0),
      CaptureVerdict.clear,
    );
  });

  test('a known recorder process censors and names itself', () {
    final v = engine().evaluate(
      const CaptureFacts(runningProcesses: ['explorer.exe', 'obs64.exe']),
      now: t0,
    );
    expect(v.censor, isTrue);
    expect(v.signals, [CaptureSignal.recorderProcess]);
    expect(v.detail, 'obs64.exe');
  });

  test(
    'process names match whole and case-insensitively, never as substrings',
    () {
      expect(
        engine()
            .evaluate(const CaptureFacts(runningProcesses: ['loom']), now: t0)
            .censor,
        isTrue,
      );
      expect(
        engine()
            .evaluate(
              const CaptureFacts(runningProcesses: ['bloomberg.exe']),
              now: t0,
            )
            .censor,
        isFalse,
      );
    },
  );

  test('OS-reported recording censors', () {
    final v = engine().evaluate(const CaptureFacts(osRecording: true), now: t0);
    expect(v.censor, isTrue);
    expect(v.signals, [CaptureSignal.osRecording]);
  });

  test('the presenter\'s own screen share is not a recording', () {
    final v = engine().evaluate(
      const CaptureFacts(osRecording: true),
      now: t0,
      ownShareActive: true,
    );
    expect(v.censor, isFalse);
  });

  test('a mirrored display censors even during the presenter\'s own share', () {
    final v = engine().evaluate(
      const CaptureFacts(osRecording: true, externalDisplay: true),
      now: t0,
      ownShareActive: true,
    );
    expect(v.censor, isTrue);
    expect(v.signals, [CaptureSignal.externalDisplay]);
  });

  test('a Remote Desktop session censors', () {
    expect(
      engine()
          .evaluate(const CaptureFacts(remoteSession: true), now: t0)
          .signals,
      [CaptureSignal.remoteSession],
    );
  });

  test('a refused block is reported but does not censor', () {
    final v = engine().evaluate(
      const CaptureFacts(),
      now: t0,
      blockFailed: true,
    );
    expect(v.censor, isFalse);
    expect(v.signals, [CaptureSignal.blockFailed]);
  });

  test(
    'censoring lifts only after the facts stay clear for the grace period',
    () {
      final e = engine();
      e.evaluate(const CaptureFacts(osRecording: true), now: t0);
      final soon = e.evaluate(
        const CaptureFacts(),
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(soon.censor, isTrue);
      expect(soon.signals, isEmpty);
      final later = e.evaluate(
        const CaptureFacts(),
        now: t0.add(const Duration(seconds: 3)),
      );
      expect(later.censor, isFalse);
    },
  );
}
