import 'json.dart';
import 'layout.dart';
import 'roles.dart';
import 'whiteboard.dart';

/// The classroom gateway protocol (ADR-0010) — packages/contracts/src/live/gateway.ts.

/// Close codes the client must not silently reconnect after.
abstract final class GatewayCloseCodes {
  static const unauthenticated = 4001;
  static const protocolError = 4002;
  static const removed = 4003;
  static const joinedElsewhere = 4009;
  static const classEnded = 4010;
}

class Hand {
  const Hand({required this.raisedSeq, required this.raisedAt});

  factory Hand.fromJson(Json j) =>
      Hand(raisedSeq: j['raisedSeq'] as int, raisedAt: j['raisedAt'] as String);

  final int raisedSeq;
  final String raisedAt;

  Json toJson() => {'raisedSeq': raisedSeq, 'raisedAt': raisedAt};
}

class ParticipantState {
  const ParticipantState({
    required this.userId,
    required this.name,
    required this.role,
    required this.caps,
    required this.grants,
    required this.revokes,
    required this.hand,
    required this.floor,
    required this.online,
    required this.capturing,
    required this.joinedAt,
  });

  factory ParticipantState.fromJson(Json j) => ParticipantState(
    userId: j['userId'] as String,
    name: j['name'] as String,
    role: ClassRole.fromWire(j['role']),
    caps: capsFromJson(j['caps']),
    grants: capsFromJson(j['grants']),
    revokes: capsFromJson(j['revokes']),
    hand: j['hand'] == null ? null : Hand.fromJson(asJson(j['hand'])),
    floor: j['floor'] as bool,
    online: j['online'] as bool,
    capturing: j['capturing'] as bool,
    joinedAt: j['joinedAt'] as String,
  );

  final String userId;
  final String name;
  final ClassRole role;

  /// Effective capabilities, computed by the server. The client never re-derives them.
  final List<Capability> caps;
  final List<Capability> grants;
  final List<Capability> revokes;
  final Hand? hand;
  final bool floor;
  final bool online;

  /// Only ever true in the view of someone with participants.manage.
  final bool capturing;
  final String joinedAt;

  bool can(Capability cap) => caps.contains(cap);

  Json toJson() => {
    'userId': userId,
    'name': name,
    'role': role.wire,
    'caps': capsToJson(caps),
    'grants': capsToJson(grants),
    'revokes': capsToJson(revokes),
    'hand': hand?.toJson(),
    'floor': floor,
    'online': online,
    'capturing': capturing,
    'joinedAt': joinedAt,
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.userId,
    required this.name,
    required this.role,
    required this.text,
    required this.at,
  });

  factory ChatMessage.fromJson(Json j) => ChatMessage(
    id: j['id'] as String,
    userId: j['userId'] as String,
    name: j['name'] as String,
    role: ClassRole.fromWire(j['role']),
    text: j['text'] as String,
    at: j['at'] as String,
  );

  final String id;
  final String userId;
  final String name;
  final ClassRole role;
  final String text;
  final String at;

  Json toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'role': role.wire,
    'text': text,
    'at': at,
  };
}

class RecordingState {
  const RecordingState({required this.active, required this.startedAt});

  factory RecordingState.fromJson(Json j) => RecordingState(
    active: j['active'] as bool,
    startedAt: j['startedAt'] as String?,
  );

  static const inactive = RecordingState(active: false, startedAt: null);

  final bool active;
  final String? startedAt;

  Json toJson() => {'active': active, 'startedAt': startedAt};
}

class ClassroomSnapshot {
  const ClassroomSnapshot({
    required this.sessionId,
    required this.classId,
    required this.title,
    required this.startedAt,
    required this.policy,
    required this.layout,
    required this.participants,
    required this.chat,
    required this.board,
    required this.recording,
  });

  factory ClassroomSnapshot.fromJson(Json j) => ClassroomSnapshot(
    sessionId: j['sessionId'] as String,
    classId: j['classId'] as String,
    title: j['title'] as String,
    startedAt: j['startedAt'] as String,
    policy: RoomPolicy.fromJson(asJson(j['policy'])),
    layout: Layout.fromJson(asJson(j['layout'])),
    participants: [
      for (final p in asJsonList(j['participants']))
        ParticipantState.fromJson(p),
    ],
    chat: [for (final m in asJsonList(j['chat'])) ChatMessage.fromJson(m)],
    board: BoardSnapshot.fromJson(asJson(j['board'])),
    recording: RecordingState.fromJson(asJson(j['recording'])),
  );

  final String sessionId;
  final String classId;
  final String title;
  final String startedAt;
  final RoomPolicy policy;
  final Layout layout;
  final List<ParticipantState> participants;
  final List<ChatMessage> chat;
  final BoardSnapshot board;
  final RecordingState recording;

  Json toJson() => {
    'sessionId': sessionId,
    'classId': classId,
    'title': title,
    'startedAt': startedAt,
    'policy': policy.toJson(),
    'layout': layout.toJson(),
    'participants': [for (final p in participants) p.toJson()],
    'chat': [for (final m in chat) m.toJson()],
    'board': board.toJson(),
    'recording': recording.toJson(),
  };
}

// ─── Commands ──────────────────────────────────────────────────────────────────

/// A command the client sends. Each is a small value; the server decides whether it is allowed.
sealed class ClassroomCommand {
  const ClassroomCommand();
  String get type;
  Json get fields => const {};
  Json toJson() => {'type': type, ...fields};

  static ClassroomCommand fromJson(Json j) {
    String user() => j['userId'] as String;
    List<Capability> caps() => capsFromJson(j['caps']);
    return switch (j['type']) {
      'hand.raise' => const RaiseHand(),
      'hand.lower' => LowerHand(j['userId'] as String?),
      'hand.lowerAll' => const LowerAllHands(),
      'floor.give' => GiveFloor(user(), video: j['video'] as bool),
      'floor.take' => TakeFloor(user()),
      'caps.grant' => GrantCaps(user(), caps()),
      'caps.revoke' => RevokeCaps(user(), caps()),
      'caps.reset' => ResetCaps(user()),
      'role.set' => SetRole(user(), ClassRole.fromWire(j['role'])),
      'policy.update' => UpdatePolicy(asJson(j['patch']).cast<String, bool>()),
      'participant.mute' => MuteParticipant(
        user(),
        MediaSource.fromWire(j['source']),
      ),
      'participant.muteAll' => const MuteAll(),
      'participant.remove' => RemoveParticipant(
        user(),
        reason: j['reason'] as String?,
      ),
      'layout.apply' => ApplyLayout(Layout.fromJson(asJson(j['layout']))),
      'chat.send' => SendChat(j['text'] as String),
      'chat.delete' => DeleteChat(j['messageId'] as String),
      'wb.add' => AddBoardItem(BoardItem.fromJson(asJson(j['item']))),
      'wb.remove' => RemoveBoardItems(listOf<String>(j['itemIds'])),
      'wb.restore' => RestoreBoardItems([
        for (final i in asJsonList(j['items'])) BoardItem.fromJson(i),
      ]),
      'wb.clear' => ClearBoardPage(j['pageId'] as String),
      'wb.page.add' => AddBoardPage(
        BoardPage.fromJson(asJson(j['page'])),
        select: j['select'] as bool,
      ),
      'wb.page.select' => SelectBoardPage(j['pageId'] as String),
      'wb.page.remove' => RemoveBoardPage(j['pageId'] as String),
      'capture.report' => ReportCapture(
        capturing: j['capturing'] as bool,
        signals: listOf<String>(j['signals']),
        detail: j['detail'] as String?,
      ),
      final t => throw ContractError('unknown command $t'),
    };
  }
}

enum MediaSource {
  audio('audio'),
  video('video'),
  screen('screen');

  const MediaSource(this.wire);
  final String wire;

  static MediaSource fromWire(Object? wire) =>
      byWire(values, wire, (v) => v.wire);
}

class RaiseHand extends ClassroomCommand {
  const RaiseHand();
  @override
  String get type => 'hand.raise';
}

class LowerHand extends ClassroomCommand {
  const LowerHand([this.userId]);
  final String? userId;
  @override
  String get type => 'hand.lower';
  @override
  Json get fields => {if (userId != null) 'userId': userId};
}

class LowerAllHands extends ClassroomCommand {
  const LowerAllHands();
  @override
  String get type => 'hand.lowerAll';
}

class GiveFloor extends ClassroomCommand {
  const GiveFloor(this.userId, {required this.video});
  final String userId;
  final bool video;
  @override
  String get type => 'floor.give';
  @override
  Json get fields => {'userId': userId, 'video': video};
}

class TakeFloor extends ClassroomCommand {
  const TakeFloor(this.userId);
  final String userId;
  @override
  String get type => 'floor.take';
  @override
  Json get fields => {'userId': userId};
}

class GrantCaps extends ClassroomCommand {
  const GrantCaps(this.userId, this.caps);
  final String userId;
  final List<Capability> caps;
  @override
  String get type => 'caps.grant';
  @override
  Json get fields => {'userId': userId, 'caps': capsToJson(caps)};
}

class RevokeCaps extends ClassroomCommand {
  const RevokeCaps(this.userId, this.caps);
  final String userId;
  final List<Capability> caps;
  @override
  String get type => 'caps.revoke';
  @override
  Json get fields => {'userId': userId, 'caps': capsToJson(caps)};
}

class ResetCaps extends ClassroomCommand {
  const ResetCaps(this.userId);
  final String userId;
  @override
  String get type => 'caps.reset';
  @override
  Json get fields => {'userId': userId};
}

class SetRole extends ClassroomCommand {
  const SetRole(this.userId, this.role);
  final String userId;
  final ClassRole role;
  @override
  String get type => 'role.set';
  @override
  Json get fields => {'userId': userId, 'role': role.wire};
}

class UpdatePolicy extends ClassroomCommand {
  const UpdatePolicy(this.patch);

  /// Keys of [RoomPolicy] to change.
  final Map<String, bool> patch;
  @override
  String get type => 'policy.update';
  @override
  Json get fields => {'patch': patch};
}

class MuteParticipant extends ClassroomCommand {
  const MuteParticipant(this.userId, this.source);
  final String userId;
  final MediaSource source;
  @override
  String get type => 'participant.mute';
  @override
  Json get fields => {'userId': userId, 'source': source.wire};
}

class MuteAll extends ClassroomCommand {
  const MuteAll();
  @override
  String get type => 'participant.muteAll';
}

class RemoveParticipant extends ClassroomCommand {
  const RemoveParticipant(this.userId, {this.reason});
  final String userId;
  final String? reason;
  @override
  String get type => 'participant.remove';
  @override
  Json get fields => {'userId': userId, if (reason != null) 'reason': reason};
}

class ApplyLayout extends ClassroomCommand {
  const ApplyLayout(this.layout);
  final Layout layout;
  @override
  String get type => 'layout.apply';
  @override
  Json get fields => {'layout': layout.toJson()};
}

class SendChat extends ClassroomCommand {
  const SendChat(this.text);
  final String text;
  @override
  String get type => 'chat.send';
  @override
  Json get fields => {'text': text};
}

class DeleteChat extends ClassroomCommand {
  const DeleteChat(this.messageId);
  final String messageId;
  @override
  String get type => 'chat.delete';
  @override
  Json get fields => {'messageId': messageId};
}

class AddBoardItem extends ClassroomCommand {
  const AddBoardItem(this.item);
  final BoardItem item;
  @override
  String get type => 'wb.add';
  @override
  Json get fields => {'item': item.toInputJson()};
}

class RemoveBoardItems extends ClassroomCommand {
  const RemoveBoardItems(this.itemIds);
  final List<String> itemIds;
  @override
  String get type => 'wb.remove';
  @override
  Json get fields => {'itemIds': itemIds};
}

class RestoreBoardItems extends ClassroomCommand {
  const RestoreBoardItems(this.items);
  final List<BoardItem> items;
  @override
  String get type => 'wb.restore';
  @override
  Json get fields => {
    'items': [for (final i in items) i.toInputJson()],
  };
}

class ClearBoardPage extends ClassroomCommand {
  const ClearBoardPage(this.pageId);
  final String pageId;
  @override
  String get type => 'wb.clear';
  @override
  Json get fields => {'pageId': pageId};
}

class AddBoardPage extends ClassroomCommand {
  const AddBoardPage(this.page, {required this.select});
  final BoardPage page;
  final bool select;
  @override
  String get type => 'wb.page.add';
  @override
  Json get fields => {'page': page.toJson(), 'select': select};
}

class SelectBoardPage extends ClassroomCommand {
  const SelectBoardPage(this.pageId);
  final String pageId;
  @override
  String get type => 'wb.page.select';
  @override
  Json get fields => {'pageId': pageId};
}

class RemoveBoardPage extends ClassroomCommand {
  const RemoveBoardPage(this.pageId);
  final String pageId;
  @override
  String get type => 'wb.page.remove';
  @override
  Json get fields => {'pageId': pageId};
}

class ReportCapture extends ClassroomCommand {
  const ReportCapture({
    required this.capturing,
    required this.signals,
    this.detail,
  });
  final bool capturing;

  /// CAPTURE_SIGNALS wire names.
  final List<String> signals;
  final String? detail;
  @override
  String get type => 'capture.report';
  @override
  Json get fields => {
    'capturing': capturing,
    'signals': signals,
    if (detail != null) 'detail': detail,
  };
}

// ─── Events ────────────────────────────────────────────────────────────────────

sealed class ClassroomEvent {
  const ClassroomEvent();
  String get type;
  Json get fields;
  Json toJson() => {'type': type, ...fields};

  static ClassroomEvent fromJson(Json j) => switch (j['type']) {
    'participant.joined' => ParticipantJoined(
      ParticipantState.fromJson(asJson(j['participant'])),
    ),
    'participant.updated' => ParticipantUpdated(
      ParticipantState.fromJson(asJson(j['participant'])),
    ),
    'participant.removed' => ParticipantRemoved(
      j['userId'] as String,
      j['reason'] as String?,
    ),
    'policy.updated' => PolicyUpdated(RoomPolicy.fromJson(asJson(j['policy']))),
    'layout.applied' => LayoutApplied(
      Layout.fromJson(asJson(j['layout'])),
      j['by'] as String,
    ),
    'chat.message' => ChatPosted(ChatMessage.fromJson(asJson(j['message']))),
    'chat.deleted' => ChatDeleted(j['messageId'] as String),
    'wb.added' => BoardItemsAdded([
      for (final i in asJsonList(j['items'])) BoardItem.fromJson(i),
    ]),
    'wb.removed' => BoardItemsRemoved(listOf<String>(j['itemIds'])),
    'wb.cleared' => BoardPageCleared(j['pageId'] as String),
    'wb.page.added' => BoardPageAdded(BoardPage.fromJson(asJson(j['page']))),
    'wb.page.selected' => BoardPageSelected(j['pageId'] as String),
    'wb.page.removed' => BoardPageRemoved(j['pageId'] as String),
    'capture.alert' => CaptureAlert(
      userId: j['userId'] as String,
      name: j['name'] as String,
      capturing: j['capturing'] as bool,
      signals: listOf<String>(j['signals']),
      detail: j['detail'] as String?,
    ),
    'media.muted' => MediaMuted(
      j['userId'] as String,
      MediaSource.fromWire(j['source']),
      j['by'] as String,
    ),
    'recording.changed' => RecordingChanged(
      RecordingState.fromJson(asJson(j['recording'])),
    ),
    'class.ended' => ClassEnded(j['reason'] as String),
    final t => throw ContractError('unknown event $t'),
  };
}

class ParticipantJoined extends ClassroomEvent {
  const ParticipantJoined(this.participant);
  final ParticipantState participant;
  @override
  String get type => 'participant.joined';
  @override
  Json get fields => {'participant': participant.toJson()};
}

class ParticipantUpdated extends ClassroomEvent {
  const ParticipantUpdated(this.participant);
  final ParticipantState participant;
  @override
  String get type => 'participant.updated';
  @override
  Json get fields => {'participant': participant.toJson()};
}

class ParticipantRemoved extends ClassroomEvent {
  const ParticipantRemoved(this.userId, this.reason);
  final String userId;
  final String? reason;
  @override
  String get type => 'participant.removed';
  @override
  Json get fields => {'userId': userId, 'reason': reason};
}

class PolicyUpdated extends ClassroomEvent {
  const PolicyUpdated(this.policy);
  final RoomPolicy policy;
  @override
  String get type => 'policy.updated';
  @override
  Json get fields => {'policy': policy.toJson()};
}

class LayoutApplied extends ClassroomEvent {
  const LayoutApplied(this.layout, this.by);
  final Layout layout;
  final String by;
  @override
  String get type => 'layout.applied';
  @override
  Json get fields => {'layout': layout.toJson(), 'by': by};
}

class ChatPosted extends ClassroomEvent {
  const ChatPosted(this.message);
  final ChatMessage message;
  @override
  String get type => 'chat.message';
  @override
  Json get fields => {'message': message.toJson()};
}

class ChatDeleted extends ClassroomEvent {
  const ChatDeleted(this.messageId);
  final String messageId;
  @override
  String get type => 'chat.deleted';
  @override
  Json get fields => {'messageId': messageId};
}

class BoardItemsAdded extends ClassroomEvent {
  const BoardItemsAdded(this.items);
  final List<BoardItem> items;
  @override
  String get type => 'wb.added';
  @override
  Json get fields => {
    'items': [for (final i in items) i.toJson()],
  };
}

class BoardItemsRemoved extends ClassroomEvent {
  const BoardItemsRemoved(this.itemIds);
  final List<String> itemIds;
  @override
  String get type => 'wb.removed';
  @override
  Json get fields => {'itemIds': itemIds};
}

class BoardPageCleared extends ClassroomEvent {
  const BoardPageCleared(this.pageId);
  final String pageId;
  @override
  String get type => 'wb.cleared';
  @override
  Json get fields => {'pageId': pageId};
}

class BoardPageAdded extends ClassroomEvent {
  const BoardPageAdded(this.page);
  final BoardPage page;
  @override
  String get type => 'wb.page.added';
  @override
  Json get fields => {'page': page.toJson()};
}

class BoardPageSelected extends ClassroomEvent {
  const BoardPageSelected(this.pageId);
  final String pageId;
  @override
  String get type => 'wb.page.selected';
  @override
  Json get fields => {'pageId': pageId};
}

class BoardPageRemoved extends ClassroomEvent {
  const BoardPageRemoved(this.pageId);
  final String pageId;
  @override
  String get type => 'wb.page.removed';
  @override
  Json get fields => {'pageId': pageId};
}

class CaptureAlert extends ClassroomEvent {
  const CaptureAlert({
    required this.userId,
    required this.name,
    required this.capturing,
    required this.signals,
    required this.detail,
  });
  final String userId;
  final String name;
  final bool capturing;
  final List<String> signals;
  final String? detail;
  @override
  String get type => 'capture.alert';
  @override
  Json get fields => {
    'userId': userId,
    'name': name,
    'capturing': capturing,
    'signals': signals,
    'detail': detail,
  };
}

class MediaMuted extends ClassroomEvent {
  const MediaMuted(this.userId, this.source, this.by);
  final String userId;
  final MediaSource source;
  final String by;
  @override
  String get type => 'media.muted';
  @override
  Json get fields => {'userId': userId, 'source': source.wire, 'by': by};
}

class RecordingChanged extends ClassroomEvent {
  const RecordingChanged(this.recording);
  final RecordingState recording;
  @override
  String get type => 'recording.changed';
  @override
  Json get fields => {'recording': recording.toJson()};
}

class ClassEnded extends ClassroomEvent {
  const ClassEnded(this.reason);

  /// `host_ended` or `timeout`.
  final String reason;
  @override
  String get type => 'class.ended';
  @override
  Json get fields => {'reason': reason};
}

// ─── Envelopes ─────────────────────────────────────────────────────────────────

class GatewayError {
  const GatewayError({
    required this.code,
    required this.message,
    required this.messageFa,
  });

  factory GatewayError.fromJson(Json j) => GatewayError(
    code: j['code'] as String,
    message: j['message'] as String,
    messageFa: j['messageFa'] as String,
  );

  final String code;
  final String message;
  final String messageFa;

  Json toJson() => {'code': code, 'message': message, 'messageFa': messageFa};
}

class SequencedEvent {
  const SequencedEvent({
    required this.seq,
    required this.at,
    required this.event,
  });

  factory SequencedEvent.fromJson(Json j) => SequencedEvent(
    seq: j['seq'] as int,
    at: j['at'] as String,
    event: ClassroomEvent.fromJson(asJson(j['evt'])),
  );

  final int seq;
  final String at;
  final ClassroomEvent event;

  Json toJson() => {'t': 'evt', 'seq': seq, 'at': at, 'evt': event.toJson()};
}

sealed class ServerMessage {
  const ServerMessage();

  static ServerMessage fromJson(Json j) => switch (j['t']) {
    'welcome' => Welcome(
      userId: asJson(j['you'])['userId'] as String,
      role: ClassRole.fromWire(asJson(j['you'])['role']),
      seq: j['seq'] as int,
      snapshot: j['snapshot'] == null
          ? null
          : ClassroomSnapshot.fromJson(asJson(j['snapshot'])),
      replay: j['replay'] == null
          ? null
          : [
              for (final e in asJsonList(j['replay']))
                SequencedEvent.fromJson(e),
            ],
    ),
    'evt' => EventMessage(SequencedEvent.fromJson(j)),
    'eph' => EphemeralMessage(
      j['from'] as String,
      BoardProgress.fromJson(asJson(j['eph'])),
    ),
    'ack' => Ack(j['id'] as String),
    'nack' => Nack(
      j['id'] as String,
      GatewayError.fromJson(asJson(j['error'])),
    ),
    'pong' => const Pong(),
    'bye' => Bye(GatewayError.fromJson(asJson(j['error']))),
    final t => throw ContractError('unknown server message $t'),
  };

  Json toJson();
}

class Welcome extends ServerMessage {
  const Welcome({
    required this.userId,
    required this.role,
    required this.seq,
    required this.snapshot,
    required this.replay,
  });
  final String userId;
  final ClassRole role;
  final int seq;
  final ClassroomSnapshot? snapshot;
  final List<SequencedEvent>? replay;

  @override
  Json toJson() => {
    't': 'welcome',
    'you': {'userId': userId, 'role': role.wire},
    'seq': seq,
    'snapshot': snapshot?.toJson(),
    'replay': replay == null ? null : [for (final e in replay!) e.toJson()],
  };
}

class EventMessage extends ServerMessage {
  const EventMessage(this.event);
  final SequencedEvent event;
  @override
  Json toJson() => event.toJson();
}

class EphemeralMessage extends ServerMessage {
  const EphemeralMessage(this.from, this.progress);
  final String from;
  final BoardProgress progress;
  @override
  Json toJson() => {'t': 'eph', 'from': from, 'eph': progress.toJson()};
}

class Ack extends ServerMessage {
  const Ack(this.id);
  final String id;
  @override
  Json toJson() => {'t': 'ack', 'id': id};
}

class Nack extends ServerMessage {
  const Nack(this.id, this.error);
  final String id;
  final GatewayError error;
  @override
  Json toJson() => {'t': 'nack', 'id': id, 'error': error.toJson()};
}

class Pong extends ServerMessage {
  const Pong();
  @override
  Json toJson() => {'t': 'pong'};
}

class Bye extends ServerMessage {
  const Bye(this.error);
  final GatewayError error;
  @override
  Json toJson() => {'t': 'bye', 'error': error.toJson()};
}

/// What the client sends. Only `hello`, `cmd`, `eph` and `ping` exist.
abstract final class ClientMessages {
  static Json hello(String ticket, int? lastSeq) => {
    't': 'hello',
    'ticket': ticket,
    'lastSeq': lastSeq,
  };
  static Json command(String id, ClassroomCommand cmd) => {
    't': 'cmd',
    'id': id,
    'cmd': cmd.toJson(),
  };
  static Json ephemeral(BoardProgress p) => {'t': 'eph', 'eph': p.toJson()};
  static const Json ping = {'t': 'ping'};
}
