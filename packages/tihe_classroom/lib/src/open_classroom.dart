import 'package:capture_guard/capture_guard.dart';

import 'contracts.dart';
import 'data/gateway_client.dart';
import 'data/live_api.dart';
import 'data/livekit_media.dart';
import 'state/classroom_session.dart';

/// Joins a live session and wires the real pieces: services/live over REST and WebSocket,
/// LiveKit for media, and capture_guard with the policy the server sent.
///
/// ```dart
/// final session = await openClassroom(
///   liveApiBaseUrl: 'https://api.tihe.ir/v1/live',
///   accessToken: auth.freshAccessToken,
///   sessionId: 'ses_01J8Z…',
/// );
/// Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClassroomPage(session: session)));
/// ```
///
/// Throws [ApiError] (with a Persian `messageFa`) when joining is refused: not enrolled, class
/// not started, locked, full, or removed.
Future<ClassroomSession> openClassroom({
  required String liveApiBaseUrl,
  required Future<String> Function() accessToken,
  required String sessionId,
}) async {
  final api = LiveApi(baseUrl: liveApiBaseUrl, accessToken: accessToken);
  final join = await api.join(sessionId);
  final policy = join.capturePolicy;
  return ClassroomSession(
    join: join,
    gateway: GatewayClient(
      url: Uri.parse(join.gatewayUrl),
      firstTicket: join.ticket,
      // Tickets live two minutes: every reconnect joins again for a fresh one.
      freshTicket: () async => (await api.join(sessionId)).ticket,
    ),
    media: LiveKitClassroomMedia(),
    capture: CaptureMonitor(
      platform: MethodChannelCaptureGuard(),
      engine: CapturePolicyEngine(
        recorderProcesses: [
          ...policy.recorderProcessesWindows,
          ...policy.recorderProcessesMacos,
        ],
      ),
      block: policy.block,
      windowsAffinity: policy.windowsAffinity == 'exclude'
          ? WindowsAffinity.exclude
          : WindowsAffinity.monitor,
      iosSecureLayer: policy.iosSecureLayer,
      scanInterval: Duration(milliseconds: policy.scanIntervalMs),
    ),
    onEndClass: () async {
      await api.end(sessionId);
    },
  );
}
