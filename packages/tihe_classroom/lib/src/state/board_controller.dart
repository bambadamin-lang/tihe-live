import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../contracts.dart';
import '../data/gateway_client.dart';
import '../domain/board_model.dart';
import '../domain/classroom_state.dart';

/// A stroke or shape this user is drawing right now.
@immutable
class Draft {
  const Draft({
    required this.id,
    required this.pageId,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    this.fill,
  });

  final String id;
  final String pageId;
  final BoardTool tool;
  final String color;
  final int width;

  /// Pens and laser: every point. Shapes: just the two corners.
  final List<int> points;
  final String? fill;
}

/// The marker tray and what the pen is doing (docs/11 §6): drafting strokes with live
/// previews for everyone else, committing them on pen-up, erasing, text, laser, and per-user
/// undo/redo. Items appear at once (optimistically) and are replaced by the server's copy.
class BoardController extends ChangeNotifier {
  BoardController({
    required this.userId,
    required Future<CommandOutcome> Function(ClassroomCommand) send,
    required void Function(BoardProgress) sendPreview,
  }) : _send = send,
       _sendPreview = sendPreview;

  final String userId;
  final Future<CommandOutcome> Function(ClassroomCommand) _send;
  final void Function(BoardProgress) _sendPreview;

  /// Previews go out about every 40 ms — smooth for others, light on the gateway.
  static const previewInterval = Duration(milliseconds: 40);

  /// Points closer than this (page units) to the last one are skipped.
  static const minStep = 12;

  final history = BoardHistory();

  BoardTool tool = BoardTool.pen;
  String color = boardPalette[1];
  bool fillShapes = false;
  final Map<String, int> widths = {...defaultToolWidth};

  Draft? draft;

  /// Sent but not yet echoed back by the server.
  final Map<String, BoardItem> pending = {};

  /// Being erased by the current eraser drag; hidden at once.
  final Set<String> erasing = {};

  /// Changes whenever [pending] or [erasing] does — what the board's finished-ink layer draws
  /// besides the room's own items — so the board rebuilds that layer then and only then, not
  /// on every pen move.
  int get committedRevision => _committedRevision;
  int _committedRevision = 0;

  void _committedChanged() {
    _committedRevision++;
    notifyListeners();
  }

  Timer? _flush;
  int _sentPoints = 0;
  bool _manage = false;

  int get width => widths[tool.name] ?? 28;

  void selectTool(BoardTool next) {
    tool = next;
    if (next == BoardTool.highlighter && color == boardPalette[1]) {
      color = boardPalette[6];
    }
    notifyListeners();
  }

  void selectColor(String hex) {
    color = hex;
    notifyListeners();
  }

  void setWidth(int value) {
    widths[tool.name] = value;
    notifyListeners();
  }

  void toggleFill() {
    fillShapes = !fillShapes;
    notifyListeners();
  }

  // ─── Pointer ──────────────────────────────────────────────────────────────

  void pointerDown(
    BoardPoint p,
    ClassroomState room, {
    required bool canManage,
  }) {
    _manage = canManage;
    final pageId = room.activePageId;
    switch (tool) {
      case BoardTool.eraser:
        if (erasing.isNotEmpty) {
          erasing.clear();
          _committedRevision++;
        }
        _erase(p, room);
      case BoardTool.text:
        return; // placed through placeText after the text is typed
      default:
        draft = Draft(
          id: newBoardItemId(),
          pageId: pageId,
          tool: tool,
          color: color,
          width: width,
          points: [p.x, p.y, p.x, p.y],
          fill:
              fillShapes &&
                  (tool == BoardTool.rect || tool == BoardTool.ellipse)
              ? color
              : null,
        );
        _sentPoints = 0;
        if (tool.penTool != null || tool == BoardTool.laser) {
          draft = _withPoints(draft!, [p.x, p.y]);
          _flush = Timer.periodic(
            previewInterval,
            (_) => _sendProgress(done: false),
          );
        }
    }
    notifyListeners();
  }

  void pointerMove(BoardPoint p, ClassroomState room) {
    final d = draft;
    if (tool == BoardTool.eraser) {
      _erase(p, room);
      return;
    }
    if (d == null) return;
    if (tool.shapeKind != null) {
      draft = _withPoints(d, [d.points[0], d.points[1], p.x, p.y]);
    } else {
      final n = d.points.length;
      final dx = p.x - d.points[n - 2], dy = p.y - d.points[n - 1];
      if (dx * dx + dy * dy < minStep * minStep) return;
      draft = _withPoints(d, [...d.points, p.x, p.y]);
    }
    notifyListeners();
  }

  Future<void> pointerUp() async {
    _flush?.cancel();
    if (tool == BoardTool.eraser) return _commitErase();
    final d = draft;
    draft = null;
    if (d == null) return;
    if (d.tool == BoardTool.laser) {
      _sendProgress(done: true, from: d);
      notifyListeners();
      return;
    }
    _sendProgress(done: true, from: d);
    final items = _itemsFrom(d);
    for (final item in items) {
      pending[item.id] = item;
    }
    history.record(ItemsAdded(items));
    _committedChanged();
    for (final item in items) {
      final outcome = await _send(AddBoardItem(item));
      if (outcome is! Accepted) {
        pending.remove(item.id);
        _committedChanged();
      }
    }
  }

  /// The server echoed items back: drop their optimistic copies.
  void confirmed(List<BoardItem> items) {
    var changed = false;
    for (final i in items) {
      changed |= pending.remove(i.id) != null;
    }
    if (changed) _committedChanged();
  }

  List<BoardItem> _itemsFrom(Draft d) {
    final pen = d.tool.penTool;
    if (pen != null) {
      return [
        for (final points in splitStroke(d.points))
          StrokeItem(
            id: points == d.points ? d.id : newBoardItemId(),
            pageId: d.pageId,
            color: d.color,
            tool: pen,
            width: d.width,
            points: points,
          ),
      ];
    }
    final shape = d.tool.shapeKind!;
    final from = (x: d.points[0], y: d.points[1]);
    final to = (x: d.points[2], y: d.points[3]);
    if ((from.x - to.x).abs() + (from.y - to.y).abs() < 40) return const [];
    return [
      ShapeItem(
        id: d.id,
        pageId: d.pageId,
        color: d.color,
        shape: shape,
        width: d.width,
        fill: d.fill,
        from: from,
        to: to,
      ),
    ];
  }

  Draft _withPoints(Draft d, List<int> points) => Draft(
    id: d.id,
    pageId: d.pageId,
    tool: d.tool,
    color: d.color,
    width: d.width,
    points: points,
    fill: d.fill,
  );

  /// Sends the points added since the last batch, at most [maxProgressPoints] per message.
  /// On pen-up the last message carries `done`, even if no new point came with it.
  void _sendProgress({required bool done, Draft? from}) {
    final d = from ?? draft;
    if (d == null || (d.tool.penTool == null && d.tool != BoardTool.laser)) {
      return;
    }
    final wire = d.tool == BoardTool.laser ? 'laser' : d.tool.penTool!.wire;
    BoardProgress batch(List<int> points, bool last) => BoardProgress(
      strokeId: d.id,
      pageId: d.pageId,
      tool: wire,
      color: d.color,
      width: d.width,
      points: points,
      done: last,
    );

    var sentDone = false;
    while (_sentPoints < d.points.length) {
      final end = min(d.points.length, _sentPoints + maxProgressPoints * 2);
      final last = done && end == d.points.length;
      _sendPreview(batch(d.points.sublist(_sentPoints, end), last));
      sentDone = last;
      _sentPoints = end;
    }
    if (done && !sentDone) {
      _sendPreview(batch(d.points.sublist(d.points.length - 2), true));
    }
  }

  // ─── Eraser ───────────────────────────────────────────────────────────────

  void _erase(BoardPoint p, ClassroomState room) {
    final candidates = [...room.itemsOn(room.activePageId), ...pending.values];
    var changed = false;
    for (final item in candidates.reversed) {
      if (erasing.contains(item.id)) continue;
      final mine = item.by == null || item.by == userId;
      if (!mine && !_manage) continue;
      if (eraserHits(item, p)) {
        erasing.add(item.id);
        changed = true;
        _erasedItems[item.id] = item;
      }
    }
    if (changed) _committedChanged();
  }

  final Map<String, BoardItem> _erasedItems = {};

  Future<void> _commitErase() async {
    if (erasing.isEmpty) return;
    final items = [for (final id in erasing) _erasedItems[id]!];
    history.record(ItemsRemoved(items));
    final ids = erasing.toList();
    await _send(RemoveBoardItems(ids));
    // Accepted: the server's wb.removed takes them off the page. Refused: they reappear.
    erasing.clear();
    _erasedItems.clear();
    _committedChanged();
  }

  // ─── Text, undo, pages ────────────────────────────────────────────────────

  Future<void> placeText(BoardPoint at, String text, String pageId) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final item = TextItem(
      id: newBoardItemId(),
      pageId: pageId,
      color: color,
      size: 380,
      at: at,
      text: trimmed.length > maxTextLength
          ? trimmed.substring(0, maxTextLength)
          : trimmed,
    );
    pending[item.id] = item;
    history.record(ItemsAdded([item]));
    _committedChanged();
    if (await _send(AddBoardItem(item)) is! Accepted) {
      pending.remove(item.id);
      _committedChanged();
    }
  }

  Future<void> undo() async {
    final command = history.undo();
    notifyListeners();
    if (command != null) await _send(command);
  }

  Future<void> redo() async {
    final command = history.redo();
    notifyListeners();
    if (command != null) await _send(command);
  }

  /// Clears the page for everyone (whiteboard.manage); undo brings it all back.
  Future<void> clearPage(ClassroomState room) async {
    final items = room.itemsOn(room.activePageId).toList();
    if (items.isEmpty) return;
    history.record(ItemsRemoved(items));
    await _send(ClearBoardPage(room.activePageId));
  }

  Future<void> addPage(BoardBackground background) => _send(
    AddBoardPage(
      BoardPage(id: newBoardPageId(), background: background),
      select: true,
    ),
  );

  Future<void> selectPage(String pageId) => _send(SelectBoardPage(pageId));

  @override
  void dispose() {
    _flush?.cancel();
    super.dispose();
  }
}
