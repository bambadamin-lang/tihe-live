import 'package:flutter/foundation.dart';

import '../../core/api/models.dart';

/// A subtitle track offered by the stream.
@immutable
class SubtitleTrack {
  const SubtitleTrack({required this.id, required this.label});

  final String id;
  final String label;
}

/// Playback state and commands: the one seam between the player UI and the video engine.
///
/// The controls read and drive this, never an engine directly, so the two engines (media_kit on
/// Windows, video_player on Android and iOS — docs/adr/0001) sit behind one surface. In M3 the
/// engine, fed by secure-core's loopback server, reports position, buffering and the stream's
/// quality and subtitle tracks here, and the commands below forward to it.
///
/// Until then nothing decodes, so [attached] is false and position moves only when the student
/// seeks. That is deliberate: the alternative is a plain player on the remote manifest, which is an
/// unprotected playback path (see PlayerScreen).
class PlayerController extends ChangeNotifier {
  PlayerController({
    required Duration duration,
    Duration initialPosition = Duration.zero,
    this.chapters = const [],
  })  : _duration = duration,
        _position = _clamp(initialPosition, duration);

  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const qualityAuto = 'auto';

  final List<Chapter> chapters;

  /// Whether an engine is producing frames. False until M3.
  bool get attached => false;

  Duration _duration;
  Duration get duration => _duration;

  Duration _position;
  Duration get position => _position;

  Duration _buffered = Duration.zero;
  Duration get buffered => _buffered;

  bool _playing = false;
  bool get playing => _playing;

  double _volume = 1;
  double get volume => _volume;

  bool _muted = false;
  bool get muted => _muted || _volume == 0;

  double _speed = 1;
  double get speed => _speed;

  /// Renditions the stream offers. Only "auto" until the engine reports the HLS variants.
  List<String> get qualities => const [qualityAuto];
  String _quality = qualityAuto;
  String get quality => _quality;

  /// Subtitle tracks the stream offers. None until the engine reports them.
  List<SubtitleTrack> get subtitleTracks => const [];
  String? _subtitle;
  String? get subtitle => _subtitle;

  double get progress =>
      _duration.inMilliseconds == 0 ? 0 : _position.inMilliseconds / _duration.inMilliseconds;

  /// The chapter the playhead is in, if any.
  Chapter? get currentChapter => chapterAt(_position);

  Chapter? chapterAt(Duration at) {
    Chapter? current;
    for (final chapter in chapters) {
      if (chapter.start <= at) current = chapter;
    }
    return current;
  }

  void togglePlay() => _playing ? pause() : play();

  void play() {
    if (_playing) return;
    // At the end, play restarts rather than doing nothing.
    if (_position >= _duration) _position = Duration.zero;
    _playing = true;
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    notifyListeners();
  }

  void seek(Duration to) {
    _position = _clamp(to, _duration);
    notifyListeners();
  }

  void seekBy(Duration delta) => seek(_position + delta);

  /// Seeks to a fraction of the duration, for the timeline.
  void seekToFraction(double fraction) =>
      seek(Duration(milliseconds: (_duration.inMilliseconds * fraction.clamp(0.0, 1.0)).round()));

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    if (_volume > 0) _muted = false;
    notifyListeners();
  }

  void toggleMute() {
    if (muted) {
      _muted = false;
      if (_volume == 0) _volume = 0.5;
    } else {
      _muted = true;
    }
    notifyListeners();
  }

  void setSpeed(double value) {
    _speed = value;
    notifyListeners();
  }

  void setQuality(String value) {
    _quality = value;
    notifyListeners();
  }

  void setSubtitle(String? trackId) {
    _subtitle = trackId;
    notifyListeners();
  }

  /// Engine callbacks (M3).
  @protected
  void reportProgress({required Duration position, Duration? buffered, Duration? duration}) {
    if (duration != null) _duration = duration;
    _position = _clamp(position, _duration);
    if (buffered != null) _buffered = _clamp(buffered, _duration);
    notifyListeners();
  }

  static Duration _clamp(Duration value, Duration max) {
    if (value < Duration.zero) return Duration.zero;
    if (value > max) return max;
    return value;
  }
}
