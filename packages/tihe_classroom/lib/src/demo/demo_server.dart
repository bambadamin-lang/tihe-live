import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';

import '../contracts.dart';
import '../data/gateway_client.dart';
import '../domain/classroom_state.dart';

/// An in-process stand-in for services/live's gateway, for the offline demo and widget tests.
///
/// It answers hello with a snapshot and turns commands into the events the real server would
/// send, checking the actor's capabilities as they are in the snapshot. It does **not**
/// implement every rule (policy changes do not recompute anyone's capabilities, for instance):
/// services/live is the authority, and its rules are tested there.
class DemoClassroomServer {
  DemoClassroomServer({required ClassroomSnapshot snapshot, int seq = 19})
    : state = ClassroomState.fromSnapshot(snapshot, seq);

  ClassroomState state;
  final List<Json> received = [];
  final List<StreamChannelController<Object?>> _clients = [];
  String? _you;
  int _chatCounter = 0;

  /// Use as `GatewayClient(connect: server.connect, …)`.
  Future<GatewayChannel> connect(Uri url) async {
    final controller = StreamChannelController<Object?>();
    _clients.add(controller);
    controller.local.stream.listen(
      (raw) => _onClient(controller, raw as String),
    );
    return StreamGatewayChannel(controller.foreign);
  }

  void _send(StreamChannelController<Object?> c, Json message) =>
      c.local.sink.add(jsonEncode(message));

  void _broadcast(Json message) {
    for (final c in _clients) {
      _send(c, message);
    }
  }

  void _onClient(StreamChannelController<Object?> c, String raw) {
    final msg = asJson(jsonDecode(raw));
    received.add(msg);
    switch (msg['t']) {
      case 'hello':
        _you ??= state.participants.keys.firstWhere(
          (id) => state.participants[id]!.role == ClassRole.host,
          orElse: () => state.participants.keys.first,
        );
        _send(
          c,
          Welcome(
            userId: _you!,
            role: state.participants[_you]?.role ?? ClassRole.participant,
            seq: state.seq,
            snapshot: state.toSnapshot(),
            replay: null,
          ).toJson(),
        );
      case 'cmd':
        final id = msg['id'] as String;
        final command = ClassroomCommand.fromJson(asJson(msg['cmd']));
        final refusal = _handle(command);
        _send(
          c,
          refusal == null ? Ack(id).toJson() : Nack(id, refusal).toJson(),
        );
      case 'ping':
        _send(c, const Pong().toJson());
    }
  }

  /// Which participant this server speaks as — set before the client says hello.
  set you(String userId) => _you = userId;

  /// Push an event as if another participant caused it (a student raising a hand, say).
  void emit(ClassroomEvent event) {
    final sequenced = SequencedEvent(
      seq: state.seq + 1,
      at: DateTime.now().toUtc().toIso8601String(),
      event: event,
    );
    state = state.apply(sequenced);
    _broadcast(sequenced.toJson());
  }

  void relay(String from, BoardProgress progress) =>
      _broadcast(EphemeralMessage(from, progress).toJson());

  GatewayError _missing(Capability cap) => GatewayError(
    code: 'CAPABILITY_MISSING',
    message: 'missing capability ${cap.wire}',
    messageFa: 'در این کلاس اجازهٔ انجام این کار را ندارید.',
  );

  ParticipantState _update(
    ParticipantState p, {
    Hand? hand,
    bool clearHand = false,
    bool? floor,
    List<Capability>? caps,
    ClassRole? role,
    bool? capturing,
  }) => ParticipantState(
    userId: p.userId,
    name: p.name,
    role: role ?? p.role,
    caps: caps ?? p.caps,
    grants: p.grants,
    revokes: p.revokes,
    hand: clearHand ? null : (hand ?? p.hand),
    floor: floor ?? p.floor,
    online: p.online,
    capturing: capturing ?? p.capturing,
    joinedAt: p.joinedAt,
  );

  GatewayError? _handle(ClassroomCommand command) {
    final me = state.participants[_you]!;
    bool lacks(Capability c) => !me.can(c);
    final now = DateTime.now().toUtc().toIso8601String();
    switch (command) {
      case RaiseHand():
        if (lacks(Capability.handRaise)) return _missing(Capability.handRaise);
        emit(
          ParticipantUpdated(
            _update(
              me,
              hand: Hand(raisedSeq: state.seq + 1, raisedAt: now),
            ),
          ),
        );
      case LowerHand(:final userId):
        final target = state.participants[userId ?? me.userId];
        if (target != null) {
          emit(ParticipantUpdated(_update(target, clearHand: true)));
        }
      case LowerAllHands():
        for (final p in state.raisedHands) {
          emit(ParticipantUpdated(_update(p, clearHand: true)));
        }
      case GiveFloor(:final userId, :final video):
        if (lacks(Capability.participantsManage)) {
          return _missing(Capability.participantsManage);
        }
        final p = state.participants[userId]!;
        emit(
          ParticipantUpdated(
            _update(
              p,
              clearHand: true,
              floor: true,
              caps: {
                ...p.caps,
                Capability.publishAudio,
                if (video) Capability.publishVideo,
              }.toList(),
            ),
          ),
        );
      case TakeFloor(:final userId):
        final p = state.participants[userId]!;
        emit(
          ParticipantUpdated(
            _update(
              p,
              floor: false,
              caps: p.caps
                  .where(
                    (c) =>
                        c != Capability.publishAudio &&
                        c != Capability.publishVideo,
                  )
                  .toList(),
            ),
          ),
        );
      case GrantCaps(:final userId, :final caps):
        final p = state.participants[userId]!;
        emit(
          ParticipantUpdated(_update(p, caps: {...p.caps, ...caps}.toList())),
        );
      case RevokeCaps(:final userId, :final caps):
        final p = state.participants[userId]!;
        emit(
          ParticipantUpdated(
            _update(p, caps: p.caps.where((c) => !caps.contains(c)).toList()),
          ),
        );
      case ResetCaps():
        break;
      case SetRole(:final userId, :final role):
        if (lacks(Capability.rolesAssign)) {
          return _missing(Capability.rolesAssign);
        }
        emit(
          ParticipantUpdated(_update(state.participants[userId]!, role: role)),
        );
      case UpdatePolicy(:final patch):
        emit(
          PolicyUpdated(
            RoomPolicy.fromJson({...state.policy.toJson(), ...patch}),
          ),
        );
      case MuteParticipant(:final userId, :final source):
        emit(MediaMuted(userId, source, me.userId));
      case MuteAll():
        break;
      case RemoveParticipant(:final userId, :final reason):
        emit(ParticipantRemoved(userId, reason));
      case ApplyLayout(:final layout):
        if (lacks(Capability.layoutChange)) {
          return _missing(Capability.layoutChange);
        }
        emit(LayoutApplied(layout, me.userId));
      case SendChat(:final text):
        if (lacks(Capability.chatSend)) return _missing(Capability.chatSend);
        emit(
          ChatPosted(
            ChatMessage(
              id: 'chm_01J8ZF${(++_chatCounter).toString().padLeft(20, '0')}',
              userId: me.userId,
              name: me.name,
              role: me.role,
              text: text,
              at: now,
            ),
          ),
        );
      case DeleteChat(:final messageId):
        emit(ChatDeleted(messageId));
      case AddBoardItem(:final item) ||
          RestoreBoardItems(items: [final item, ...]):
        if (lacks(Capability.whiteboardDraw)) {
          return _missing(Capability.whiteboardDraw);
        }
        final items = command is RestoreBoardItems ? command.items : [item];
        emit(
          BoardItemsAdded([
            for (final i in items)
              BoardItem.fromJson({
                ...i.toInputJson(),
                'by': me.userId,
                'seq': state.seq + 1,
              }),
          ]),
        );
      case RestoreBoardItems():
        break;
      case RemoveBoardItems(:final itemIds):
        emit(BoardItemsRemoved(itemIds));
      case ClearBoardPage(:final pageId):
        emit(BoardPageCleared(pageId));
      case AddBoardPage(:final page, :final select):
        emit(BoardPageAdded(page));
        if (select) emit(BoardPageSelected(page.id));
      case SelectBoardPage(:final pageId):
        emit(BoardPageSelected(pageId));
      case RemoveBoardPage(:final pageId):
        emit(BoardPageRemoved(pageId));
      case ReportCapture(:final capturing, :final signals, :final detail):
        emit(ParticipantUpdated(_update(me, capturing: capturing)));
        emit(
          CaptureAlert(
            userId: me.userId,
            name: me.name,
            capturing: capturing,
            signals: signals,
            detail: detail,
          ),
        );
    }
    return null;
  }
}
