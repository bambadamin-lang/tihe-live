import 'dart:async';

import 'package:capture_guard/capture_guard.dart';
import 'package:flutter/foundation.dart';

import '../contracts.dart';
import '../data/gateway_client.dart';
import '../data/media.dart';
import '../domain/classroom_state.dart';
import 'board_controller.dart';

/// Why this client left the class — decides what the exit screen says.
enum ClassroomExit { left, ended, removed, joinedElsewhere, lostAccess }

enum NoticeTone { info, success, warning, alert }

@immutable
class ClassroomNotice {
  const ClassroomNotice(this.id, this.textFa, this.tone);
  final int id;
  final String textFa;
  final NoticeTone tone;
}

/// Another person's stroke in progress, or their laser trail (never stored).
@immutable
class RemotePreview {
  const RemotePreview({
    required this.strokeId,
    required this.from,
    required this.pageId,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    required this.updatedAt,
    this.revealFrom,
  });

  final String strokeId;
  final String from;
  final String pageId;
  final String tool;
  final String color;
  final int width;
  final List<int> points;
  final DateTime updatedAt;

  /// How much of [points] was already on screen before the latest batch. Batches arrive about
  /// every [BoardController.previewInterval]; the board reveals each one across that interval
  /// so the stroke glides at the display's rate instead of jumping 25 times a second. Null
  /// shows everything at once.
  final int? revealFrom;

  bool get isLaser => tool == 'laser';

  /// Still revealing its latest batch at [now].
  bool glidingAt(DateTime now) =>
      !isLaser &&
      revealFrom != null &&
      revealFrom! < points.length &&
      now.difference(updatedAt) < BoardController.previewInterval;

  /// The part of [points] to draw at [now].
  List<int> revealedAt(DateTime now) {
    final from = revealFrom;
    if (isLaser || from == null || from >= points.length) return points;
    final elapsed = now.difference(updatedAt).inMicroseconds;
    final f = (elapsed / BoardController.previewInterval.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    var n = from + ((points.length - from) * f).round();
    n -= n % 2; // whole points only: x and y travel together
    return n >= points.length ? points : points.sublist(0, n);
  }
}

/// Everything the classroom UI draws, in one immutable value.
@immutable
class ClassroomView {
  const ClassroomView({
    required this.userId,
    required this.name,
    required this.initialRole,
    required this.classTitle,
    required this.watermark,
    this.room,
    this.gateway = GatewayStatus.connecting,
    this.media = const MediaState(),
    this.capture = CaptureVerdict.clear,
    this.previews = const {},
    this.notices = const [],
    this.exit,
    this.exitMessageFa,
  });

  final String userId;
  final String name;
  final ClassRole initialRole;
  final String classTitle;
  final WatermarkSpec watermark;
  final ClassroomState? room;
  final GatewayStatus gateway;
  final MediaState media;
  final CaptureVerdict capture;
  final Map<String, RemotePreview> previews;
  final List<ClassroomNotice> notices;
  final ClassroomExit? exit;
  final String? exitMessageFa;

  ParticipantState? get me => room?.participants[userId];
  ClassRole get role => me?.role ?? initialRole;
  bool can(Capability cap) => me?.can(cap) ?? false;

  /// Hosts see who is being censored right now (only they receive the flag).
  List<ParticipantState> get capturing =>
      room?.participants.values.where((p) => p.capturing).toList() ?? const [];

  ClassroomView copyWith({
    ClassroomState? room,
    GatewayStatus? gateway,
    MediaState? media,
    CaptureVerdict? capture,
    Map<String, RemotePreview>? previews,
    List<ClassroomNotice>? notices,
    ClassroomExit? exit,
    String? exitMessageFa,
  }) => ClassroomView(
    userId: userId,
    name: name,
    initialRole: initialRole,
    classTitle: classTitle,
    watermark: watermark,
    room: room ?? this.room,
    gateway: gateway ?? this.gateway,
    media: media ?? this.media,
    capture: capture ?? this.capture,
    previews: previews ?? this.previews,
    notices: notices ?? this.notices,
    exit: exit ?? this.exit,
    exitMessageFa: exitMessageFa ?? this.exitMessageFa,
  );
}

/// One class, from join to exit: applies gateway events to the stage, keeps media in line with
/// what the server allows, runs the capture guard, and exposes commands to the widgets. No
/// widget talks to the gateway, LiveKit or the capture plugin directly.
class ClassroomSession {
  ClassroomSession({
    required JoinResponse join,
    required this.gateway,
    required this.media,
    this.capture,
    this.onEndClass,
    DateTime Function()? clock,
  }) : _join = join,
       _clock = clock ?? DateTime.now,
       view = ValueNotifier(
         ClassroomView(
           userId: join.userId,
           name: join.name,
           initialRole: join.role,
           classTitle: join.classTitle,
           watermark: join.watermark,
         ),
       ) {
    board = BoardController(
      userId: join.userId,
      send: send,
      sendPreview: gateway.sendEphemeral,
    );
  }

  final JoinResponse _join;
  final GatewayClient gateway;
  final ClassroomMedia media;
  final CaptureMonitor? capture;

  /// Ends the class for everyone (host): services/live `POST /sessions/:id/end`.
  final Future<void> Function()? onEndClass;
  final DateTime Function() _clock;
  final ValueNotifier<ClassroomView> view;
  late final BoardController board;

  final _subscriptions = <StreamSubscription<Object?>>[];
  final _noticeTimers = <Timer>{};
  Timer? _sweep;
  bool _disposed = false;
  int _noticeCounter = 0;

  ClassroomView get _v => view.value;
  set _v(ClassroomView next) => view.value = next;

  Future<void> open() async {
    _v = _v.copyWith(media: media.state);
    gateway.status.addListener(_onStatus);
    _subscriptions
      ..add(gateway.messages.listen(_onMessage))
      ..add(gateway.closures.listen(_onBye))
      ..add(
        media.changes.listen((m) {
          _v = _v.copyWith(media: m);
          capture?.ownShareActive = m.local?.screenOn ?? false;
        }),
      );
    final guard = capture;
    if (guard != null) {
      _subscriptions
        ..add(guard.verdicts.listen(_onVerdict))
        ..add(
          guard.reports.listen(
            (r) => send(
              ReportCapture(
                capturing: r.capturing,
                signals: [for (final s in r.signals) s.wire],
                detail: r.detail,
              ),
            ),
          ),
        );
      await guard.start();
    }
    _sweep = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _sweepPreviews(),
    );
    await gateway.open();
    try {
      await media.connect(_join.livekitUrl, _join.livekitToken);
    } on Object {
      _notice(
        'اتصال صوت و تصویر برقرار نشد. کلاس بدون صوت و تصویر ادامه می‌یابد.',
        NoticeTone.warning,
      );
    }
  }

  void _onStatus() => _v = _v.copyWith(gateway: gateway.status.value);

  void _onVerdict(CaptureVerdict verdict) {
    final wasCensored = _v.capture.censor;
    _v = _v.copyWith(capture: verdict);
    if (verdict.censor != wasCensored && _join.capturePolicy.censorAudio) {
      media.setRemoteAudioMuted(verdict.censor);
    }
  }

  void _onMessage(ServerMessage msg) {
    switch (msg) {
      case Welcome(:final snapshot, :final replay, :final seq):
        var room = snapshot != null
            ? ClassroomState.fromSnapshot(snapshot, seq)
            : _v.room;
        for (final e in replay ?? const <SequencedEvent>[]) {
          room = room?.apply(e);
        }
        _v = _v.copyWith(room: room);
        _afterRoomChange(null);
      case EventMessage(:final event):
        final before = _v.room;
        if (before == null) return;
        _v = _v.copyWith(room: before.apply(event));
        _onEvent(event.event, before);
      case EphemeralMessage(:final from, :final progress):
        if (from == _v.userId) return;
        final existing = _v.previews[progress.strokeId];
        _v = _v.copyWith(
          previews: {
            ..._v.previews,
            progress.strokeId: RemotePreview(
              strokeId: progress.strokeId,
              from: from,
              pageId: progress.pageId,
              tool: progress.tool,
              color: progress.color,
              width: progress.width,
              points: [...?existing?.points, ...progress.points],
              updatedAt: _clock(),
              revealFrom: existing?.points.length ?? 0,
            ),
          },
        );
      case Ack() || Nack() || Pong() || Bye():
        break;
    }
  }

  void _onEvent(ClassroomEvent event, ClassroomState before) {
    final me = _v.userId;
    switch (event) {
      case ParticipantUpdated(:final participant) when participant.userId == me:
        _afterRoomChange(before.participants[me]);
      case MediaMuted(:final userId, :final source) when userId == me:
        final what = switch (source) {
          MediaSource.audio => 'میکروفون',
          MediaSource.video => 'دوربین',
          MediaSource.screen => 'اشتراک صفحه',
        };
        _notice('میزبان $what شما را قطع کرد.', NoticeTone.warning);
      case CaptureAlert(
        :final name,
        :final capturing,
        :final detail,
        :final signals,
      ):
        final how = signals.contains('screenshot')
            ? 'از صفحه عکس گرفت'
            : signals.contains('block_failed')
            ? 'روی دستگاهی است که جلوی ضبط را نمی‌گیرد'
            : capturing
            ? 'در حال ضبط صفحه است${detail == null ? '' : ' ($detail)'}'
            : 'ضبط صفحه را متوقف کرد';
        _notice('$name $how', capturing ? NoticeTone.alert : NoticeTone.info);
      case BoardItemsAdded(:final items):
        board.confirmed(items);
        final ids = {for (final i in items) i.id};
        if (_v.previews.keys.any(ids.contains)) {
          _v = _v.copyWith(
            previews: {
              for (final e in _v.previews.entries)
                if (!ids.contains(e.key)) e.key: e.value,
            },
          );
        }
      case BoardPageCleared(:final pageId) || BoardPageRemoved(:final pageId):
        board.history.forgetPage(pageId);
      case ClassEnded():
        _exit(ClassroomExit.ended, 'کلاس به پایان رسید.');
      case ParticipantRemoved(:final userId) when userId == me:
        _exit(ClassroomExit.removed, 'میزبان شما را از کلاس خارج کرده است.');
      default:
        break;
    }
  }

  /// Keeps media and the capture guard in line with what the room now allows this user.
  void _afterRoomChange(ParticipantState? previous) {
    final now = _v.me;
    if (now == null) return;
    final local = _v.media.local;
    if (!now.can(Capability.publishAudio) && (local?.micOn ?? false)) {
      media.setMicrophone(false);
    }
    if (!now.can(Capability.publishVideo) && (local?.cameraOn ?? false)) {
      media.setCamera(false);
    }
    if (!now.can(Capability.publishScreen) && (local?.screenOn ?? false)) {
      media.stopScreenShare();
    }

    if (previous != null && !previous.floor && now.floor) {
      _notice('اجازهٔ صحبت دارید؛ میکروفون را روشن کنید.', NoticeTone.success);
    }
    if (previous != null && previous.role != now.role) {
      _notice('نقش شما در کلاس: ${now.role.labelFa}', NoticeTone.info);
    }
    // Presenters vanish from captures instead of showing a black box (ADR-0011).
    capture?.setWindowsAffinity(
      now.role.rank >= ClassRole.presenter.rank
          ? WindowsAffinity.exclude
          : WindowsAffinity.monitor,
    );
  }

  void _onBye(GatewayError error) {
    final exit = switch (error.code) {
      'REMOVED_FROM_CLASS' => ClassroomExit.removed,
      'JOINED_ELSEWHERE' => ClassroomExit.joinedElsewhere,
      'CLASS_ENDED' => ClassroomExit.ended,
      _ => ClassroomExit.lostAccess,
    };
    _exit(exit, error.messageFa);
  }

  void _exit(ClassroomExit exit, String messageFa) {
    if (_v.exit != null) return;
    _v = _v.copyWith(exit: exit, exitMessageFa: messageFa);
  }

  void _sweepPreviews() {
    final now = _clock();
    final stale = _v.previews.values.where((p) {
      final age = now.difference(p.updatedAt);
      return age >
          (p.isLaser
              ? const Duration(milliseconds: 1500)
              : const Duration(seconds: 5));
    });
    if (stale.isEmpty) return;
    final gone = {for (final p in stale) p.strokeId};
    _v = _v.copyWith(
      previews: {
        for (final e in _v.previews.entries)
          if (!gone.contains(e.key)) e.key: e.value,
      },
    );
  }

  void _notice(String textFa, NoticeTone tone) {
    final notice = ClassroomNotice(++_noticeCounter, textFa, tone);
    _v = _v.copyWith(notices: [..._v.notices, notice]);
    late final Timer timer;
    timer = Timer(const Duration(seconds: 6), () {
      _noticeTimers.remove(timer);
      dismissNotice(notice.id);
    });
    _noticeTimers.add(timer);
  }

  void dismissNotice(int id) {
    if (_disposed || _v.notices.every((n) => n.id != id)) return;
    _v = _v.copyWith(notices: _v.notices.where((n) => n.id != id).toList());
  }

  /// Sends a command; a refusal is shown to the user in the server's own Persian words.
  Future<CommandOutcome> send(ClassroomCommand command) async {
    final outcome = await gateway.send(command);
    switch (outcome) {
      case Refused(:final error):
        _notice(error.messageFa, NoticeTone.warning);
      case NoAnswer() when command is! ReportCapture:
        _notice(
          'ارتباط با کلاس برقرار نیست. دوباره تلاش کنید.',
          NoticeTone.warning,
        );
      case _:
        break;
    }
    return outcome;
  }

  // ─── Actions the controls call ──────────────────────────────────────────────

  Future<void> toggleMicrophone() async {
    final on = _v.media.local?.micOn ?? false;
    if (!on && !_v.can(Capability.publishAudio)) {
      _notice('برای صحبت، دست خود را بالا ببرید.', NoticeTone.info);
      return;
    }
    await media.setMicrophone(!on);
  }

  Future<void> toggleCamera() async {
    final on = _v.media.local?.cameraOn ?? false;
    if (!on && !_v.can(Capability.publishVideo)) return;
    await media.setCamera(!on);
  }

  Future<List<ScreenSource>> screenSources() => media.screenSources();

  Future<void> startScreenShare([ScreenSource? source]) async {
    if (!_v.can(Capability.publishScreen)) return;
    await media.startScreenShare(source);
  }

  Future<void> stopScreenShare() => media.stopScreenShare();

  Future<void> toggleHand() =>
      send(_v.me?.hand == null ? const RaiseHand() : const LowerHand());

  Future<void> leave() async => _exit(ClassroomExit.left, 'از کلاس خارج شدید.');

  Future<void> endClass() async {
    await onEndClass?.call();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Every timer stops synchronously, before anything is awaited.
    _sweep?.cancel();
    for (final t in _noticeTimers) {
      t.cancel();
    }
    gateway.status.removeListener(_onStatus);
    final closing = gateway.close();
    final cancelling = [for (final s in _subscriptions) s.cancel()];
    final guard = capture?.dispose();
    board.dispose();
    await Future.wait([closing, ...cancelling, ?guard, media.dispose()]);
  }
}
