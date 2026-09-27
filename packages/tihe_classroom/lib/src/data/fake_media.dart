import 'dart:async';

import 'package:flutter/widgets.dart';

import 'media.dart';

/// Media without a media server: for tests, golden screenshots and the offline demo. Videos
/// are drawn by [painter] (a coloured card with the person's initial, by default in the demo).
class FakeClassroomMedia implements ClassroomMedia {
  FakeClassroomMedia({
    required this.localUserId,
    MediaState? initial,
    Widget Function(String userId, VideoSlot slot)? painter,
  }) : _state = initial ?? const MediaState(connected: true),
       _painter = painter ?? ((_, _) => const SizedBox.expand());

  final String localUserId;
  final Widget Function(String userId, VideoSlot slot) _painter;
  final _changes = StreamController<MediaState>.broadcast();
  MediaState _state;
  bool remoteAudioMuted = false;
  final calls = <String>[];

  @override
  MediaState get state => _state;
  @override
  Stream<MediaState> get changes => _changes.stream;

  void emit(MediaState state) {
    _state = state;
    _changes.add(state);
  }

  void _updateLocal(ParticipantMedia Function(ParticipantMedia) f) {
    final me = _state.of(localUserId);
    emit(
      MediaState(
        connected: true,
        activeSpeaker: _state.activeSpeaker,
        participants: {..._state.participants, localUserId: f(me)},
      ),
    );
  }

  @override
  Future<void> connect(String url, String token) async => calls.add('connect');

  @override
  Future<void> setMicrophone(bool on) async {
    calls.add('mic:$on');
    _updateLocal(
      (m) => ParticipantMedia(
        userId: m.userId,
        micOn: on,
        cameraOn: m.cameraOn,
        screenOn: m.screenOn,
        isLocal: true,
      ),
    );
  }

  @override
  Future<void> setCamera(bool on) async {
    calls.add('camera:$on');
    _updateLocal(
      (m) => ParticipantMedia(
        userId: m.userId,
        micOn: m.micOn,
        cameraOn: on,
        screenOn: m.screenOn,
        isLocal: true,
      ),
    );
  }

  @override
  Future<List<ScreenSource>> screenSources() async => const [
    ScreenSource(id: 'screen:0', name: 'صفحهٔ اصلی', isScreen: true),
    ScreenSource(id: 'window:1', name: 'PowerPoint — مشتق', isScreen: false),
  ];

  @override
  Future<void> startScreenShare([ScreenSource? source]) async {
    calls.add('share:${source?.id}');
    _updateLocal(
      (m) => ParticipantMedia(
        userId: m.userId,
        micOn: m.micOn,
        cameraOn: m.cameraOn,
        screenOn: true,
        isLocal: true,
      ),
    );
  }

  @override
  Future<void> stopScreenShare() async {
    calls.add('share:stop');
    _updateLocal(
      (m) => ParticipantMedia(
        userId: m.userId,
        micOn: m.micOn,
        cameraOn: m.cameraOn,
        isLocal: true,
      ),
    );
  }

  @override
  Future<void> setRemoteAudioMuted(bool muted) async {
    remoteAudioMuted = muted;
    calls.add('remoteAudio:${muted ? 'muted' : 'on'}');
  }

  @override
  Widget video(String userId, VideoSlot slot, {BoxFit fit = BoxFit.cover}) =>
      _painter(userId, slot);

  @override
  Future<void> dispose() async => _changes.close();
}
