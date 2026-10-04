import 'dart:async';
import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import 'media.dart';

/// [ClassroomMedia] on LiveKit. Publish rights are enforced by the SFU from the server side
/// (the gateway pushes them); this class only asks, and reports what LiveKit says is live.
class LiveKitClassroomMedia implements ClassroomMedia {
  LiveKitClassroomMedia({this.placeholder = _emptyPlaceholder});

  /// Drawn where there is no video (camera off, nothing shared).
  final Widget Function(String userId, VideoSlot slot) placeholder;

  static Widget _emptyPlaceholder(String userId, VideoSlot slot) =>
      const SizedBox.expand();

  /// Screen shares run at 30 fps, so scrolling, cursor moves and software demos look smooth.
  static const screenShareFrameRate = 30;

  /// 1080p at up to 30 fps, capped at 3 Mbps rather than LiveKit's 5: many teachers' uploads
  /// cannot carry more. When bandwidth runs short, WebRTC keeps a screen share's resolution
  /// and drops frames instead, so slide text stays sharp.
  static const screenShareParams = VideoParameters(
    dimensions: VideoDimensionsPresets.h1080_169,
    encoding: VideoEncoding(
      maxBitrate: 3000 * 1000,
      maxFramerate: screenShareFrameRate,
    ),
  );

  final Room _room = Room(
    roomOptions: const RoomOptions(
      // Only the resolutions actually on screen are received — a 100-person gallery would
      // otherwise download 100 full streams.
      adaptiveStream: true,
      dynacast: true,
      defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
      defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
        maxFrameRate: screenShareFrameRate + 0.0,
        params: screenShareParams,
      ),
    ),
  );
  EventsListener<RoomEvent>? _listener;
  final _changes = StreamController<MediaState>.broadcast();
  MediaState _state = const MediaState();
  bool _remoteMuted = false;

  @override
  MediaState get state => _state;

  @override
  Stream<MediaState> get changes => _changes.stream;

  @override
  Future<void> connect(String url, String token) async {
    _listener = _room.createListener()
      ..on<TrackSubscribedEvent>((e) async {
        // Censoring must also cover audio that starts after it began.
        if (_remoteMuted && e.track is RemoteAudioTrack) {
          await e.track.disable();
        }
      })
      ..listen((_) => _refresh());
    await _room.connect(url, token);
    _refresh();
  }

  void _refresh() {
    final participants = <String, ParticipantMedia>{};
    final local = _room.localParticipant;
    if (local != null) {
      participants[local.identity] = _describe(local, isLocal: true);
    }
    for (final p in _room.remoteParticipants.values) {
      participants[p.identity] = _describe(p, isLocal: false);
    }
    _state = MediaState(
      connected: _room.connectionState == ConnectionState.connected,
      participants: participants,
      activeSpeaker: _room.activeSpeakers.firstOrNull?.identity,
    );
    if (!_changes.isClosed) _changes.add(_state);
  }

  ParticipantMedia _describe(Participant p, {required bool isLocal}) =>
      ParticipantMedia(
        userId: p.identity,
        micOn: p.isMicrophoneEnabled(),
        cameraOn: _track(p, TrackSource.camera) != null,
        screenOn: _track(p, TrackSource.screenShareVideo) != null,
        speaking: p.isSpeaking,
        isLocal: isLocal,
      );

  VideoTrack? _track(Participant p, TrackSource source) {
    final pub = p.videoTrackPublications.firstWhereOrNull(
      (t) => t.source == source && !t.muted,
    );
    final track = pub?.track;
    return track is VideoTrack ? track : null;
  }

  Participant? _participant(String userId) {
    final local = _room.localParticipant;
    if (local?.identity == userId) return local;
    return _room.remoteParticipants.values.firstWhereOrNull(
      (p) => p.identity == userId,
    );
  }

  @override
  Future<void> setMicrophone(bool on) async {
    await _room.localParticipant?.setMicrophoneEnabled(on);
    _refresh();
  }

  @override
  Future<void> setCamera(bool on) async {
    await _room.localParticipant?.setCameraEnabled(on);
    _refresh();
  }

  @override
  Future<List<ScreenSource>> screenSources() async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return const [];
    }
    final sources = await rtc.desktopCapturer.getSources(
      types: [rtc.SourceType.Screen, rtc.SourceType.Window],
    );
    return [
      for (final s in sources)
        ScreenSource(
          id: s.id,
          name: s.name,
          isScreen: s.type == rtc.SourceType.Screen,
          thumbnail: s.thumbnail,
        ),
    ];
  }

  @override
  Future<void> startScreenShare([ScreenSource? source]) async {
    await _room.localParticipant?.setScreenShareEnabled(
      true,
      screenShareCaptureOptions: ScreenShareCaptureOptions(
        sourceId: source?.id,
        maxFrameRate: screenShareFrameRate + 0.0,
        params: screenShareParams,
        // iOS shares the whole device only through the Broadcast Upload Extension (docs/11 §7).
        useiOSBroadcastExtension: !kIsWeb && Platform.isIOS,
      ),
    );
    _refresh();
  }

  @override
  Future<void> stopScreenShare() async {
    await _room.localParticipant?.setScreenShareEnabled(false);
    _refresh();
  }

  @override
  Future<List<MediaDeviceOption>> devices(MediaDeviceKind kind) async {
    final found = await _hardware(kind);
    final current = switch (kind) {
      MediaDeviceKind.microphone => _room.selectedAudioInputDeviceId,
      MediaDeviceKind.camera => _room.selectedVideoInputDeviceId,
    };
    final noun = kind == MediaDeviceKind.microphone ? 'میکروفون' : 'دوربین';
    return [
      for (final (i, d) in found.indexed)
        MediaDeviceOption(
          id: d.deviceId,
          // Browsers and some drivers hide names until permission is given.
          label: d.label.isEmpty ? '$noun ${i + 1}' : d.label,
          selected: d.deviceId == current,
        ),
    ];
  }

  @override
  Future<void> selectDevice(MediaDeviceKind kind, String deviceId) async {
    final device = (await _hardware(
      kind,
    )).firstWhereOrNull((d) => d.deviceId == deviceId);
    if (device == null) return;
    switch (kind) {
      case MediaDeviceKind.microphone:
        await _room.setAudioInputDevice(device);
      case MediaDeviceKind.camera:
        await _room.setVideoInputDevice(device);
    }
    _refresh();
  }

  Future<List<MediaDevice>> _hardware(MediaDeviceKind kind) =>
      kind == MediaDeviceKind.microphone
      ? Hardware.instance.audioInputs()
      : Hardware.instance.videoInputs();

  @override
  Future<void> setRemoteAudioMuted(bool muted) async {
    _remoteMuted = muted;
    for (final p in _room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final track = pub.track;
        if (track == null) continue;
        muted ? await track.disable() : await track.enable();
      }
    }
  }

  @override
  Widget video(String userId, VideoSlot slot, {BoxFit fit = BoxFit.cover}) {
    final p = _participant(userId);
    final track = p == null
        ? null
        : _track(
            p,
            slot == VideoSlot.camera
                ? TrackSource.camera
                : TrackSource.screenShareVideo,
          );
    if (track == null) return placeholder(userId, slot);
    return VideoTrackRenderer(
      track,
      key: ValueKey('${track.sid}-$fit'),
      fit: fit == BoxFit.contain ? VideoViewFit.contain : VideoViewFit.cover,
    );
  }

  @override
  Future<void> dispose() async {
    await _listener?.dispose();
    await _room.disconnect();
    await _room.dispose();
    await _changes.close();
  }
}
