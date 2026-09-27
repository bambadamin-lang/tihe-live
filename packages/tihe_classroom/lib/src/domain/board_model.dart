import 'dart:math';
import 'dart:ui';

import '../contracts.dart';

/// Pure whiteboard logic: page ↔ screen mapping, hit-testing for the eraser, and per-user
/// undo/redo as inverse commands (docs/11 §6). No widgets, no sockets — all tested directly.

/// Maps between the fixed 16000 × 9000 page and a widget of any size, letterboxed at 16:9.
class BoardViewport {
  BoardViewport(Size size) {
    const aspect = boardWidth / boardHeight;
    final w = min(size.width, size.height * aspect);
    final h = w / aspect;
    page = Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  /// The page's rectangle inside the widget.
  late final Rect page;

  double get scale => page.width / boardWidth;

  BoardPoint toPage(Offset local) => (
    x: ((local.dx - page.left) / scale).round().clamp(0, boardWidth),
    y: ((local.dy - page.top) / scale).round().clamp(0, boardHeight),
  );

  Offset toLocal(int x, int y) =>
      Offset(page.left + x * scale, page.top + y * scale);
}

double _distanceToSegment(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx;
  final cy = ay + t * dy;
  return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

/// Whether an eraser of [radius] page units at [p] touches [item].
bool eraserHits(BoardItem item, BoardPoint p, {int radius = 120}) {
  final x = p.x.toDouble();
  final y = p.y.toDouble();
  switch (item) {
    case StrokeItem(:final points, :final width):
      final reach = radius + width / 2;
      if (points.length == 2) {
        return sqrt(pow(x - points[0], 2) + pow(y - points[1], 2)) <= reach;
      }
      for (var i = 0; i + 3 < points.length; i += 2) {
        final d = _distanceToSegment(
          x,
          y,
          points[i].toDouble(),
          points[i + 1].toDouble(),
          points[i + 2].toDouble(),
          points[i + 3].toDouble(),
        );
        if (d <= reach) return true;
      }
      return false;
    case ShapeItem(
      :final shape,
      :final from,
      :final to,
      :final width,
      :final fill,
    ):
      final reach = radius + width / 2;
      final l = min(from.x, to.x).toDouble(), r = max(from.x, to.x).toDouble();
      final t = min(from.y, to.y).toDouble(), b = max(from.y, to.y).toDouble();
      switch (shape) {
        case ShapeKind.line || ShapeKind.arrow:
          return _distanceToSegment(
                x,
                y,
                from.x.toDouble(),
                from.y.toDouble(),
                to.x.toDouble(),
                to.y.toDouble(),
              ) <=
              reach;
        case ShapeKind.rect:
          final inside = x >= l && x <= r && y >= t && y <= b;
          if (inside && fill != null) return true;
          final edge = [
            _distanceToSegment(x, y, l, t, r, t),
            _distanceToSegment(x, y, r, t, r, b),
            _distanceToSegment(x, y, r, b, l, b),
            _distanceToSegment(x, y, l, b, l, t),
          ].reduce(min);
          return edge <= reach;
        case ShapeKind.ellipse:
          final rx = max(1.0, (r - l) / 2), ry = max(1.0, (b - t) / 2);
          final nx = (x - (l + rx)) / rx, ny = (y - (t + ry)) / ry;
          final d = sqrt(nx * nx + ny * ny);
          if (fill != null && d <= 1) return true;
          return (d - 1).abs() * min(rx, ry) <= reach;
      }
    case TextItem(:final at, :final size, :final text):
      final lines = text.split('\n');
      final longest = lines.map((line) => line.length).reduce(max);
      // Persian text anchors at its start (right) edge and runs leftwards.
      final w = longest * size * 0.55;
      final h = lines.length * size * 1.4;
      return x <= at.x + radius &&
          x >= at.x - w - radius &&
          y >= at.y - radius &&
          y <= at.y + h + radius;
  }
}

/// One step this user can undo.
sealed class BoardAction {
  const BoardAction();
}

/// Items this user added. Undo removes them.
class ItemsAdded extends BoardAction {
  const ItemsAdded(this.items);
  final List<BoardItem> items;
}

/// Items this user erased or cleared. Undo restores them.
class ItemsRemoved extends BoardAction {
  const ItemsRemoved(this.items);
  final List<BoardItem> items;
}

/// Per-user undo/redo. Each step is an inverse command, so undoing never touches anyone else's
/// work, and the server re-checks it like any other command.
class BoardHistory {
  static const limit = 100;
  final List<BoardAction> _undo = [];
  final List<BoardAction> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void record(BoardAction action) {
    _undo.add(action);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  /// The command that undoes the last step, or null.
  ClassroomCommand? undo() {
    if (_undo.isEmpty) return null;
    final action = _undo.removeLast();
    _redo.add(action);
    return _inverse(action);
  }

  ClassroomCommand? redo() {
    if (_redo.isEmpty) return null;
    final action = _redo.removeLast();
    _undo.add(action);
    return _forward(action);
  }

  /// A page was cleared or removed by someone: steps on it can no longer be undone sensibly.
  void forgetPage(String pageId) {
    bool onPage(BoardAction a) => switch (a) {
      ItemsAdded(:final items) ||
      ItemsRemoved(:final items) => items.every((i) => i.pageId == pageId),
    };
    _undo.removeWhere(onPage);
    _redo.removeWhere(onPage);
  }

  static ClassroomCommand _inverse(BoardAction a) => switch (a) {
    ItemsAdded(:final items) => RemoveBoardItems([for (final i in items) i.id]),
    ItemsRemoved(:final items) => RestoreBoardItems(items),
  };

  static ClassroomCommand _forward(BoardAction a) => switch (a) {
    ItemsAdded(:final items) => RestoreBoardItems(items),
    ItemsRemoved(:final items) => RemoveBoardItems([
      for (final i in items) i.id,
    ]),
  };
}

/// Splits a long stroke into items of at most [maxStrokePoints] points, overlapping by one point
/// so the pieces join without a gap.
List<List<int>> splitStroke(List<int> points) {
  const maxInts = maxStrokePoints * 2;
  if (points.length <= maxInts) return [points];
  final pieces = <List<int>>[];
  var start = 0;
  while (start < points.length - 2) {
    final end = min(start + maxInts, points.length);
    pieces.add(points.sublist(start, end));
    if (end == points.length) break;
    start = end - 2;
  }
  return pieces;
}
