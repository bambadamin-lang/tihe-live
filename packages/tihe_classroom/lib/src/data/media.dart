import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Camera, microphone and screen share, as the classroom needs them — behind an interface so
/// widgets never import LiveKit and tests and the demo run without a media server.
@immutable
class ParticipantMedia {
  const ParticipantMedia({
    required this.userId,
    this.micOn = false,
    this.cameraOn = false,
    this.screenOn = false,
    this.speaking = false,
    this.isLocal = false,
  });

  final String userId;
  final bool micOn;
  final bool cameraOn;
  final bool screenOn;
  final bool speaking;
  final bool isLocal;
}

@immutable
class MediaState {
  const MediaState({
    this.connected = false,
    this.participants = const {},
    this.activeSpeaker,
  });

  final bool connected;
  final Map<String, ParticipantMedia> participants;
  final String? activeSpeaker;

  ParticipantMedia of(String userId) =>
      participants[userId] ?? ParticipantMedia(userId: userId);

  ParticipantMedia? get local {
    for (final p in participants.values) {
      if (p.isLocal) return p;
    }
    return null;
  }

  /// The first participant sharing a screen, preferring [preferred] (the host) when they are.
  String? screenSharer({Iterable<String> preferred = const []}) {
    for (final id in preferred) {
      if (participants[id]?.screenOn ?? false) return id;
    }
    for (final p in participants.values) {
      if (p.screenOn) return p.userId;
    }
    return null;
  }
}

/// A screen or window offered in the desktop share picker.
@immutable
class ScreenSource {
  const ScreenSource({
    required this.id,
    required this.name,
    required this.isScreen,
    this.thumbnail,
  });

  final String id;
  final String name;
  final bool isScreen;
  final Uint8List? thumbnail;
}

enum VideoSlot { camera, screen }

abstract class ClassroomMedia {
  MediaState get state;
  Stream<MediaState> get changes;

  Future<void> connect(String url, String token);
  Future<void> setMicrophone(bool on);
  Future<void> setCamera(bool on);

  /// Desktop: screens and windows to choose from. Empty on mobile, where the OS picks.
  Future<List<ScreenSource>> screenSources();
  Future<void> startScreenShare([ScreenSource? source]);
  Future<void> stopScreenShare();

  /// Censoring mutes the class too: capture blocking never covers audio (ADR-0011).
  Future<void> setRemoteAudioMuted(bool muted);

  /// The video of [userId], or a placeholder when there is none.
  Widget video(String userId, VideoSlot slot, {BoxFit fit = BoxFit.cover});

  Future<void> dispose();
}
