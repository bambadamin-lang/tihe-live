import 'package:meta/meta.dart';

import '../contracts.dart';

/// One classroom as this client sees it. Changes **only** through [apply], with the same
/// semantics as `applyEvent` in services/live/src/core/room-state.ts — so this stage, every
/// other stage, the server and the recording all agree.
@immutable
class ClassroomState {
  const ClassroomState({
    required this.sessionId,
    required this.classId,
    required this.title,
    required this.startedAt,
    required this.policy,
    required this.layout,
    required this.participants,
    required this.chat,
    required this.pages,
    required this.activePageId,
    required this.items,
    required this.recording,
    required this.seq,
    this.ended = false,
    this.endReason,
  });

  factory ClassroomState.fromSnapshot(ClassroomSnapshot s, int seq) =>
      ClassroomState(
        sessionId: s.sessionId,
        classId: s.classId,
        title: s.title,
        startedAt: s.startedAt,
        policy: s.policy,
        layout: s.layout,
        participants: {for (final p in s.participants) p.userId: p},
        chat: s.chat,
        pages: s.board.pages,
        activePageId: s.board.activePageId,
        items: {for (final i in s.board.items) i.id: i},
        recording: s.recording,
        seq: seq,
      );

  final String sessionId;
  final String classId;
  final String title;
  final String startedAt;
  final RoomPolicy policy;
  final Layout layout;

  /// In join order (a Dart map literal keeps insertion order).
  final Map<String, ParticipantState> participants;
  final List<ChatMessage> chat;
  final List<BoardPage> pages;
  final String activePageId;

  /// In sequence order, which is paint order.
  final Map<String, BoardItem> items;
  final RecordingState recording;
  final int seq;
  final bool ended;
  final String? endReason;

  static const chatLimit = 200;

  /// Back to the wire shape — what a server would send a newcomer.
  ClassroomSnapshot toSnapshot() => ClassroomSnapshot(
    sessionId: sessionId,
    classId: classId,
    title: title,
    startedAt: startedAt,
    policy: policy,
    layout: layout,
    participants: participants.values.toList(),
    chat: chat,
    board: BoardSnapshot(
      pages: pages,
      activePageId: activePageId,
      items: items.values.toList(),
    ),
    recording: recording,
  );

  BoardPage? get activePage {
    for (final p in pages) {
      if (p.id == activePageId) return p;
    }
    return pages.isEmpty ? null : pages.first;
  }

  Iterable<BoardItem> itemsOn(String pageId) =>
      items.values.where((i) => i.pageId == pageId);

  /// Raised hands in the order the server received them.
  List<ParticipantState> get raisedHands =>
      participants.values.where((p) => p.hand != null).toList()
        ..sort((a, b) => a.hand!.raisedSeq.compareTo(b.hand!.raisedSeq));

  List<ParticipantState> get online =>
      participants.values.where((p) => p.online).toList();

  ClassroomState _copy({
    RoomPolicy? policy,
    Layout? layout,
    Map<String, ParticipantState>? participants,
    List<ChatMessage>? chat,
    List<BoardPage>? pages,
    String? activePageId,
    Map<String, BoardItem>? items,
    RecordingState? recording,
    required int seq,
    bool? ended,
    String? endReason,
  }) => ClassroomState(
    sessionId: sessionId,
    classId: classId,
    title: title,
    startedAt: startedAt,
    policy: policy ?? this.policy,
    layout: layout ?? this.layout,
    participants: participants ?? this.participants,
    chat: chat ?? this.chat,
    pages: pages ?? this.pages,
    activePageId: activePageId ?? this.activePageId,
    items: items ?? this.items,
    recording: recording ?? this.recording,
    seq: seq,
    ended: ended ?? this.ended,
    endReason: endReason ?? this.endReason,
  );

  /// Apply one sequenced event. Events at or below the current sequence are ignored, so a
  /// replay that overlaps what was already applied is harmless.
  ClassroomState apply(SequencedEvent e) {
    if (e.seq <= seq) return this;
    final s = e.seq;
    switch (e.event) {
      case ParticipantJoined(:final participant) ||
          ParticipantUpdated(:final participant):
        return _copy(
          seq: s,
          participants: {...participants, participant.userId: participant},
        );
      case ParticipantRemoved(:final userId):
        return _copy(seq: s, participants: {...participants}..remove(userId));
      case PolicyUpdated(:final policy):
        return _copy(seq: s, policy: policy);
      case LayoutApplied(:final layout):
        return _copy(seq: s, layout: layout);
      case ChatPosted(:final message):
        final next = [...chat, message];
        return _copy(
          seq: s,
          chat: next.length > chatLimit
              ? next.sublist(next.length - chatLimit)
              : next,
        );
      case ChatDeleted(:final messageId):
        return _copy(
          seq: s,
          chat: chat.where((m) => m.id != messageId).toList(),
        );
      case BoardItemsAdded(items: final added):
        return _copy(seq: s, items: {...items, for (final i in added) i.id: i});
      case BoardItemsRemoved(:final itemIds):
        final gone = itemIds.toSet();
        return _copy(
          seq: s,
          items: {
            for (final i in items.values)
              if (!gone.contains(i.id)) i.id: i,
          },
        );
      case BoardPageCleared(:final pageId) || BoardPageRemoved(:final pageId):
        final removed = e.event is BoardPageRemoved;
        return _copy(
          seq: s,
          pages: removed ? pages.where((p) => p.id != pageId).toList() : null,
          items: {
            for (final i in items.values)
              if (i.pageId != pageId) i.id: i,
          },
        );
      case BoardPageAdded(:final page):
        return _copy(seq: s, pages: [...pages, page]);
      case BoardPageSelected(:final pageId):
        return _copy(seq: s, activePageId: pageId);
      case RecordingChanged(:final recording):
        return _copy(seq: s, recording: recording);
      case ClassEnded(:final reason):
        return _copy(seq: s, ended: true, endReason: reason);
      case CaptureAlert() || MediaMuted():
        // Notifications, handled by the session; they change nothing on the stage.
        return _copy(seq: s);
    }
  }
}
