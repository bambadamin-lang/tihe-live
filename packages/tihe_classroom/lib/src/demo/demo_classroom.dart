import 'dart:math';

import 'package:capture_guard/capture_guard.dart';
import 'package:flutter/material.dart';

import '../contracts.dart';
import '../data/fake_media.dart';
import '../data/gateway_client.dart';
import '../data/media.dart';
import '../state/classroom_session.dart';
import 'demo_server.dart';

/// A believable class for the offline demo and screenshots: a maths lecture in progress, with a
/// board, a chat, raised hands and people on camera. All data is invented.
abstract final class DemoClassroom {
  static const host = 'usr_01J8ZB00000000000000000001';
  static const cohost = 'usr_01J8ZB00000000000000000002';
  static const ali = 'usr_01J8ZB00000000000000000003';
  static const sara = 'usr_01J8ZB00000000000000000004';
  static const page1 = 'wbp_01J8ZD00000000000000000001';
  static const page2 = 'wbp_01J8ZD00000000000000000002';

  static const _allHost = [
    Capability.publishAudio,
    Capability.publishVideo,
    Capability.publishScreen,
    Capability.whiteboardDraw,
    Capability.whiteboardManage,
    Capability.chatSend,
    Capability.participantsManage,
    Capability.rolesAssign,
    Capability.layoutChange,
    Capability.recordingControl,
    Capability.classEnd,
  ];

  static ParticipantState _p(
    String id,
    String name,
    ClassRole role,
    List<Capability> caps, {
    Hand? hand,
    bool floor = false,
    bool online = true,
  }) => ParticipantState(
    userId: id,
    name: name,
    role: role,
    caps: caps,
    grants: const [],
    revokes: const [],
    hand: hand,
    floor: floor,
    online: online,
    capturing: false,
    joinedAt: '2026-09-27T06:30:00.000Z',
  );

  static const _student = [
    Capability.publishVideo,
    Capability.chatSend,
    Capability.handRaise,
  ];

  static List<ParticipantState> get participants => [
    _p(host, 'دکتر رضایی', ClassRole.host, _allHost),
    _p(cohost, 'مریم احمدی', ClassRole.cohost, const [
      Capability.publishAudio,
      Capability.publishVideo,
      Capability.publishScreen,
      Capability.whiteboardDraw,
      Capability.whiteboardManage,
      Capability.chatSend,
      Capability.participantsManage,
      Capability.layoutChange,
    ]),
    _p(
      ali,
      'علی کریمی',
      ClassRole.participant,
      _student,
      hand: const Hand(raisedSeq: 12, raisedAt: '2026-09-27T06:41:00.000Z'),
    ),
    _p(sara, 'سارا محمدی', ClassRole.participant, const [
      ..._student,
      Capability.publishAudio,
    ], floor: true),
    _p(
      'usr_01J8ZB00000000000000000005',
      'رضا نوری',
      ClassRole.participant,
      _student,
      hand: const Hand(raisedSeq: 15, raisedAt: '2026-09-27T06:44:00.000Z'),
    ),
    _p(
      'usr_01J8ZB00000000000000000006',
      'نگار حسینی',
      ClassRole.participant,
      _student,
    ),
    _p(
      'usr_01J8ZB00000000000000000007',
      'امیر صادقی',
      ClassRole.participant,
      _student,
    ),
    _p(
      'usr_01J8ZB00000000000000000008',
      'فاطمه موسوی',
      ClassRole.participant,
      _student,
    ),
    _p(
      'usr_01J8ZB00000000000000000009',
      'حسین رحیمی',
      ClassRole.participant,
      _student,
      online: false,
    ),
  ];

  static List<BoardItem> get boardItems {
    StrokeItem stroke(
      String id,
      List<int> points, {
      String color = '#1F4FD8',
      PenTool tool = PenTool.pen,
      int width = 30,
    }) => StrokeItem(
      id: id,
      pageId: page1,
      color: color,
      tool: tool,
      width: width,
      points: points,
      by: host,
      seq: 10,
    );
    // y = x² sketched as a pen stroke.
    final parabola = <int>[];
    for (var x = -30; x <= 30; x++) {
      parabola
        ..add(3400 + x * 70)
        ..add(7600 - (x * x * 3.4).round());
    }
    return [
      stroke(
        'wbi_01J8ZE00000000000000000001',
        [900, 8200, 5900, 8200],
        color: '#1B1B1F',
        width: 22,
      ),
      stroke(
        'wbi_01J8ZE00000000000000000002',
        [3400, 8600, 3400, 3900],
        color: '#1B1B1F',
        width: 22,
      ),
      stroke(
        'wbi_01J8ZE00000000000000000003',
        parabola,
        color: '#D32F2F',
        width: 36,
      ),
      stroke(
        'wbi_01J8ZE00000000000000000004',
        [
          for (var x = 8700; x <= 14800; x += 200) ...[
            x,
            1650 + (x ~/ 200 % 3) * 6,
          ],
        ],
        tool: PenTool.highlighter,
        color: '#FFD600',
        width: 260,
      ),
      TextItem(
        id: 'wbi_01J8ZE00000000000000000005',
        pageId: page1,
        color: '#1B1B1F',
        size: 520,
        at: (x: 15000, y: 1300),
        text: 'مشتق توابع مرکب',
        by: host,
        seq: 11,
      ),
      TextItem(
        id: 'wbi_01J8ZE00000000000000000006',
        pageId: page1,
        color: '#1F4FD8',
        size: 420,
        at: (x: 15000, y: 2600),
        text: "(f(g(x)))′ = f′(g(x)) · g′(x)",
        by: host,
        seq: 12,
      ),
      TextItem(
        id: 'wbi_01J8ZE00000000000000000007',
        pageId: page1,
        color: '#2E7D32',
        size: 360,
        at: (x: 15000, y: 4300),
        text: 'مثال: y = sin(x²)\ny′ = 2x · cos(x²)',
        by: cohost,
        seq: 13,
      ),
      ShapeItem(
        id: 'wbi_01J8ZE00000000000000000008',
        pageId: page1,
        color: '#D32F2F',
        shape: ShapeKind.rect,
        width: 30,
        fill: null,
        from: (x: 8300, y: 4100),
        to: (x: 15300, y: 6500),
        by: host,
        seq: 14,
      ),
      ShapeItem(
        id: 'wbi_01J8ZE00000000000000000009',
        pageId: page1,
        color: '#F57C00',
        shape: ShapeKind.arrow,
        width: 34,
        fill: null,
        from: (x: 8100, y: 5400),
        to: (x: 5200, y: 6600),
        by: host,
        seq: 15,
      ),
    ];
  }

  static List<ChatMessage> get chat => [
    ChatMessage(
      id: 'chm_01J8ZF00000000000000000001',
      userId: ali,
      name: 'علی کریمی',
      role: ClassRole.participant,
      text: 'سلام استاد، صدا خوب است.',
      at: '2026-09-27T06:31:00.000Z',
    ),
    ChatMessage(
      id: 'chm_01J8ZF00000000000000000002',
      userId: host,
      name: 'دکتر رضایی',
      role: ClassRole.host,
      text: 'سلام، شروع می‌کنیم. امروز قاعدهٔ زنجیره‌ای.',
      at: '2026-09-27T06:32:00.000Z',
    ),
    ChatMessage(
      id: 'chm_01J8ZF00000000000000000003',
      userId: sara,
      name: 'سارا محمدی',
      role: ClassRole.participant,
      text: 'در مثال دوم چرا ضریب ۲ آمد؟',
      at: '2026-09-27T06:43:00.000Z',
    ),
    ChatMessage(
      id: 'chm_01J8ZF00000000000000000004',
      userId: cohost,
      name: 'مریم احمدی',
      role: ClassRole.cohost,
      text: 'از مشتق x² می‌آید؛ روی تخته نوشتم.',
      at: '2026-09-27T06:44:00.000Z',
    ),
  ];

  static ClassroomSnapshot snapshot({Layout? layout}) => ClassroomSnapshot(
    sessionId: 'ses_01J8ZC00000000000000000001',
    classId: 'cls_01J8ZA00000000000000000001',
    title: 'ریاضی ۱ — جلسهٔ چهارم',
    startedAt: DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 47, seconds: 12))
        .toIso8601String(),
    policy: const RoomPolicy(
      participantsCanUnmute: false,
      participantsCanStartVideo: true,
      participantsCanShareScreen: false,
      participantsCanDraw: false,
      participantsCanChat: true,
      handRaiseEnabled: true,
      locked: false,
    ),
    layout: layout ?? layoutPresets[LayoutPreset.whiteboard]!,
    participants: participants,
    chat: chat,
    board: BoardSnapshot(
      pages: const [
        BoardPage(id: page1, background: BoardBackground.grid),
        BoardPage(id: page2, background: BoardBackground.plain),
      ],
      activePageId: page1,
      items: boardItems,
    ),
    recording: RecordingState(
      active: true,
      startedAt: DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 47))
          .toIso8601String(),
    ),
  );

  static JoinResponse join({required String as}) {
    final me = participants.firstWhere((p) => p.userId == as);
    return JoinResponse(
      session: const LiveSession(
        id: 'ses_01J8ZC00000000000000000001',
        classId: 'cls_01J8ZA00000000000000000001',
        status: 'live',
        startedAt: '2026-09-27T06:30:00.000Z',
        endedAt: null,
        recording: RecordingState(
          active: true,
          startedAt: '2026-09-27T06:30:00.000Z',
        ),
      ),
      classTitle: 'ریاضی ۱ — جلسهٔ چهارم',
      userId: as,
      name: me.name,
      role: me.role,
      livekitUrl: 'ws://demo',
      livekitToken: 'demo',
      gatewayUrl: 'ws://demo/v1/live/ws',
      ticket: 'demo-ticket',
      ticketExpiresAt: '2026-09-27T06:32:00.000Z',
      watermark: WatermarkSpec(
        text:
            '0912•••${as.substring(as.length - 4)} · #${watermarkShortId(as)}',
        opacity: 0.32,
        fontSize: 13,
        movement: 'corners',
        periodSeconds: 30,
        seed: 918273,
      ),
      capturePolicy: const CapturePolicySpec(
        block: true,
        windowsAffinity: 'monitor',
        censorAudio: true,
        reportToHost: true,
        recorderProcessesWindows: ['obs64.exe'],
        recorderProcessesMacos: ['obs'],
        iosSecureLayer: false,
        scanIntervalMs: 3000,
      ),
    );
  }

  /// Who is on camera, talking and sharing in the demo.
  static MediaState media({
    required String localUserId,
    bool hostSharing = false,
  }) {
    ParticipantMedia m(
      String id, {
      bool mic = false,
      bool cam = false,
      bool screen = false,
      bool speaking = false,
    }) => ParticipantMedia(
      userId: id,
      micOn: mic,
      cameraOn: cam,
      screenOn: screen,
      speaking: speaking,
      isLocal: id == localUserId,
    );
    return MediaState(
      connected: true,
      activeSpeaker: host,
      participants: {
        host: m(
          host,
          mic: true,
          cam: true,
          screen: hostSharing,
          speaking: true,
        ),
        cohost: m(cohost, cam: true),
        ali: m(ali, cam: true),
        sara: m(sara, mic: true, cam: true),
        'usr_01J8ZB00000000000000000005': m(
          'usr_01J8ZB00000000000000000005',
          cam: true,
        ),
        'usr_01J8ZB00000000000000000006': m('usr_01J8ZB00000000000000000006'),
        'usr_01J8ZB00000000000000000007': m(
          'usr_01J8ZB00000000000000000007',
          cam: true,
        ),
        'usr_01J8ZB00000000000000000008': m('usr_01J8ZB00000000000000000008'),
      },
    );
  }

  /// A running demo class as [as], with the in-process server to script it from.
  static ({
    ClassroomSession session,
    DemoClassroomServer server,
    FakeClassroomMedia media,
  })
  build({
    String as = host,
    Layout? layout,
    bool hostSharing = false,
    CaptureMonitor? capture,
  }) {
    final server = DemoClassroomServer(snapshot: snapshot(layout: layout))
      ..you = as;
    final media = FakeClassroomMedia(
      localUserId: as,
      initial: DemoClassroom.media(localUserId: as, hostSharing: hostSharing),
      painter: (userId, slot) => DemoVideo(userId: userId, slot: slot),
    );
    final session = ClassroomSession(
      join: join(as: as),
      gateway: GatewayClient(
        url: Uri.parse('ws://demo/v1/live/ws'),
        firstTicket: 'demo-ticket',
        freshTicket: () async => 'demo-ticket',
        connect: server.connect,
      ),
      media: media,
      capture: capture,
      onEndClass: () async => server.emit(const ClassEnded('host_ended')),
    );
    return (session: session, server: server, media: media);
  }
}

/// Painted stand-in for a webcam or a shared screen in the demo.
class DemoVideo extends StatelessWidget {
  const DemoVideo({super.key, required this.userId, required this.slot});

  final String userId;
  final VideoSlot slot;

  @override
  Widget build(BuildContext context) {
    if (slot == VideoSlot.screen) return const _DemoSlide();
    final hue = [
      24.0,
      200.0,
      150.0,
      330.0,
      42.0,
      270.0,
    ][userId.hashCode.abs() % 6];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.1,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.25, 0.62).toColor(),
            HSLColor.fromAHSL(1, hue, 0.22, 0.30).toColor(),
            HSLColor.fromAHSL(1, hue, 0.2, 0.14).toColor(),
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Align(
          alignment: const Alignment(0, 0.9),
          child: Icon(
            Icons.person,
            size: min(box.maxWidth * 0.55, box.maxHeight * 0.9),
            color: Colors.black.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _DemoSlide extends StatelessWidget {
  const _DemoSlide();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF1D2B3A),
    child: Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(24),
          color: Colors.white,
          child: FittedBox(
            alignment: AlignmentDirectional.topStart,
            // Dark ink on the white slide, whatever the app's theme.
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Color(0xFF1D2B3A)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'قاعدهٔ زنجیره‌ای',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1D2B3A),
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    '•  اگر y = f(u) و u = g(x)',
                    style: TextStyle(fontSize: 22),
                  ),
                  Text(
                    '•  آنگاه dy/dx = dy/du · du/dx',
                    style: TextStyle(fontSize: 22),
                  ),
                  Text(
                    // The formula is isolated (LRI … PDI) so the bidi algorithm keeps it in one piece.
                    '•  مثال: \u2066(sin x²)′ = 2x cos x²\u2069',
                    style: TextStyle(fontSize: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
