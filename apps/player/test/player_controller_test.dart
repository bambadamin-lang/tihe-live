import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_player/core/api/models.dart';
import 'package:tihe_player/features/player/player_controller.dart';

/// The controller is what every player control drives, and what the engine will report into, so
/// its arithmetic — clamping, resume, chapter lookup — is guarded here rather than discovered on a
/// student's screen.
void main() {
  PlayerController controller({Duration initial = Duration.zero}) => PlayerController(
    duration: const Duration(minutes: 60),
    initialPosition: initial,
    chapters: const [
      Chapter(id: 'c1', title: 'intro', start: Duration.zero),
      Chapter(id: 'c2', title: 'limits', start: Duration(minutes: 10)),
      Chapter(id: 'c3', title: 'exercises', start: Duration(minutes: 40)),
    ],
  );

  test('starts at the resume point, clamped to the duration', () {
    expect(controller(initial: const Duration(minutes: 18)).position, const Duration(minutes: 18));
    expect(controller(initial: const Duration(hours: 3)).position, const Duration(minutes: 60));
    expect(controller(initial: const Duration(minutes: -1)).position, Duration.zero);
  });

  test('seeking is clamped at both ends', () {
    final c = controller(initial: const Duration(minutes: 1));
    c.seekBy(const Duration(minutes: -5));
    expect(c.position, Duration.zero);
    c.seekBy(const Duration(hours: 2));
    expect(c.position, const Duration(minutes: 60));
  });

  test('seekToFraction maps the timeline onto the duration', () {
    final c = controller()..seekToFraction(0.25);
    expect(c.position, const Duration(minutes: 15));
    c.seekToFraction(1.7);
    expect(c.position, const Duration(minutes: 60));
  });

  test('play at the end restarts from the beginning', () {
    final c = controller(initial: const Duration(minutes: 60))..play();
    expect(c.playing, isTrue);
    expect(c.position, Duration.zero);
  });

  test('the current chapter follows the playhead', () {
    final c = controller(initial: const Duration(minutes: 12));
    expect(c.currentChapter?.id, 'c2');
    c.seek(const Duration(minutes: 40));
    expect(c.currentChapter?.id, 'c3');
    c.seek(const Duration(minutes: 9, seconds: 59));
    expect(c.currentChapter?.id, 'c1');
  });

  test('muting keeps the volume, and unmuting from zero restores something audible', () {
    final c = controller()..setVolume(0.7);
    c.toggleMute();
    expect(c.muted, isTrue);
    expect(c.volume, 0.7);
    c.toggleMute();
    expect(c.muted, isFalse);

    c.setVolume(0);
    expect(c.muted, isTrue);
    c.toggleMute();
    expect(c.muted, isFalse);
    expect(c.volume, greaterThan(0));
  });

  test('volume is clamped', () {
    final c = controller()..setVolume(1.4);
    expect(c.volume, 1);
    c.setVolume(-0.2);
    expect(c.volume, 0);
  });

  test('nothing decodes until the engine attaches', () {
    // The M0 player must not claim to be playing video it cannot show.
    expect(controller().attached, isFalse);
  });
}
