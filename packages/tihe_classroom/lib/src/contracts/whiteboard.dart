import 'dart:ui' show Color;

import 'json.dart';

/// The shared whiteboard (docs/11 §6). Page space is a fixed 16:9 integer grid; mirrors
/// packages/contracts/src/live/whiteboard.ts, with pen styles checked against
/// fixtures/live/board-styles.json so the live board and the recording draw alike.
const boardWidth = 16000;
const boardHeight = 9000;
const maxStrokePoints = 2000;
const maxProgressPoints = 100;
const maxTextLength = 500;
const maxPages = 50;

enum PenTool {
  pen('pen', 'خودکار'),
  marker('marker', 'ماژیک'),
  highlighter('highlighter', 'ماژیک فسفری');

  const PenTool(this.wire, this.labelFa);
  final String wire;
  final String labelFa;

  static PenTool fromWire(Object? wire) => byWire(values, wire, (v) => v.wire);
}

enum ShapeKind {
  line('line', 'خط'),
  arrow('arrow', 'پیکان'),
  rect('rect', 'مستطیل'),
  ellipse('ellipse', 'بیضی');

  const ShapeKind(this.wire, this.labelFa);
  final String wire;
  final String labelFa;

  static ShapeKind fromWire(Object? wire) =>
      byWire(values, wire, (v) => v.wire);
}

/// Everything in the marker tray.
enum BoardTool {
  pen('خودکار'),
  marker('ماژیک'),
  highlighter('ماژیک فسفری'),
  line('خط'),
  arrow('پیکان'),
  rect('مستطیل'),
  ellipse('بیضی'),
  text('متن'),
  eraser('پاک‌کن'),
  laser('لیزر');

  const BoardTool(this.labelFa);
  final String labelFa;

  PenTool? get penTool => switch (this) {
    BoardTool.pen => PenTool.pen,
    BoardTool.marker => PenTool.marker,
    BoardTool.highlighter => PenTool.highlighter,
    _ => null,
  };

  ShapeKind? get shapeKind => switch (this) {
    BoardTool.line => ShapeKind.line,
    BoardTool.arrow => ShapeKind.arrow,
    BoardTool.rect => ShapeKind.rect,
    BoardTool.ellipse => ShapeKind.ellipse,
    _ => null,
  };
}

/// perfect-freehand settings per pen — the same numbers as PEN_STYLES in the contract.
class PenStyle {
  const PenStyle({
    required this.thinning,
    required this.smoothing,
    required this.streamline,
    required this.simulatePressure,
    required this.opacity,
    required this.underlay,
  });

  final double thinning;
  final double smoothing;
  final double streamline;
  final bool simulatePressure;
  final double opacity;

  /// Drawn beneath ink, multiplied, like a real highlighter over print.
  final bool underlay;

  Json toJson() => {
    'thinning': thinning,
    'smoothing': smoothing,
    'streamline': streamline,
    'simulatePressure': simulatePressure,
    'opacity': opacity,
    'underlay': underlay,
  };
}

const penStyles = {
  PenTool.pen: PenStyle(
    thinning: 0.55,
    smoothing: 0.5,
    streamline: 0.45,
    simulatePressure: true,
    opacity: 1,
    underlay: false,
  ),
  PenTool.marker: PenStyle(
    thinning: 0,
    smoothing: 0.6,
    streamline: 0.5,
    simulatePressure: false,
    opacity: 1,
    underlay: false,
  ),
  PenTool.highlighter: PenStyle(
    thinning: 0,
    smoothing: 0.7,
    streamline: 0.6,
    simulatePressure: false,
    opacity: 0.35,
    underlay: true,
  ),
};

/// Starting widths in page units — DEFAULT_TOOL_WIDTH in the contract.
const defaultToolWidth = {
  'pen': 28,
  'marker': 70,
  'highlighter': 240,
  'line': 28,
  'arrow': 28,
  'rect': 28,
  'ellipse': 28,
  'laser': 60,
};

/// Marker-tray colours — BOARD_PALETTE in the contract.
const boardPalette = [
  '#1B1B1F',
  '#1F4FD8',
  '#D32F2F',
  '#2E7D32',
  '#F57C00',
  '#7B1FA2',
  '#FFD600',
  '#FFFFFF',
];

Color colorFromHex(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

String colorToHex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

enum BoardBackground {
  plain('plain', 'ساده'),
  grid('grid', 'شطرنجی'),
  lines('lines', 'خط‌دار'),
  dots('dots', 'نقطه‌ای');

  const BoardBackground(this.wire, this.labelFa);
  final String wire;
  final String labelFa;

  static BoardBackground fromWire(Object? wire) =>
      byWire(values, wire, (v) => v.wire);
}

class BoardPage {
  const BoardPage({required this.id, required this.background});

  factory BoardPage.fromJson(Json j) => BoardPage(
    id: j['id'] as String,
    background: BoardBackground.fromWire(j['background']),
  );

  final String id;
  final BoardBackground background;

  Json toJson() => {'id': id, 'background': background.wire};
}

typedef BoardPoint = ({int x, int y});

BoardPoint _point(Object? json) {
  final l = json as List;
  return (x: l[0] as int, y: l[1] as int);
}

List<int> _pointJson(BoardPoint p) => [p.x, p.y];

/// One stored item. `by` and `seq` are set by the server; they are null on an item the client
/// is about to send.
sealed class BoardItem {
  const BoardItem({
    required this.id,
    required this.pageId,
    required this.color,
    this.by,
    this.seq,
  });

  factory BoardItem.fromJson(Json j) => switch (j['kind']) {
    'stroke' => StrokeItem(
      id: j['id'] as String,
      pageId: j['pageId'] as String,
      color: j['color'] as String,
      tool: PenTool.fromWire(j['tool']),
      width: j['width'] as int,
      points: listOf<int>(j['points']),
      by: j['by'] as String?,
      seq: j['seq'] as int?,
    ),
    'shape' => ShapeItem(
      id: j['id'] as String,
      pageId: j['pageId'] as String,
      color: j['color'] as String,
      shape: ShapeKind.fromWire(j['shape']),
      width: j['width'] as int,
      fill: j['fill'] as String?,
      from: _point(j['from']),
      to: _point(j['to']),
      by: j['by'] as String?,
      seq: j['seq'] as int?,
    ),
    'text' => TextItem(
      id: j['id'] as String,
      pageId: j['pageId'] as String,
      color: j['color'] as String,
      size: j['size'] as int,
      at: _point(j['at']),
      text: j['text'] as String,
      by: j['by'] as String?,
      seq: j['seq'] as int?,
    ),
    final kind => throw ContractError('unknown board item kind $kind'),
  };

  final String id;
  final String pageId;
  final String color;
  final String? by;
  final int? seq;

  /// Without `by`/`seq`: what the client sends in wb.add and wb.restore.
  Json toInputJson();

  Json toJson() => {
    ...toInputJson(),
    if (by != null) 'by': by,
    if (seq != null) 'seq': seq,
  };
}

class StrokeItem extends BoardItem {
  const StrokeItem({
    required super.id,
    required super.pageId,
    required super.color,
    required this.tool,
    required this.width,
    required this.points,
    super.by,
    super.seq,
  });

  final PenTool tool;
  final int width;

  /// Flat `[x0, y0, x1, y1, …]` in page units.
  final List<int> points;

  @override
  Json toInputJson() => {
    'kind': 'stroke',
    'id': id,
    'pageId': pageId,
    'color': color,
    'tool': tool.wire,
    'width': width,
    'points': points,
  };
}

class ShapeItem extends BoardItem {
  const ShapeItem({
    required super.id,
    required super.pageId,
    required super.color,
    required this.shape,
    required this.width,
    required this.fill,
    required this.from,
    required this.to,
    super.by,
    super.seq,
  });

  final ShapeKind shape;
  final int width;
  final String? fill;
  final BoardPoint from;
  final BoardPoint to;

  @override
  Json toInputJson() => {
    'kind': 'shape',
    'id': id,
    'pageId': pageId,
    'color': color,
    'shape': shape.wire,
    'width': width,
    'fill': fill,
    'from': _pointJson(from),
    'to': _pointJson(to),
  };
}

class TextItem extends BoardItem {
  const TextItem({
    required super.id,
    required super.pageId,
    required super.color,
    required this.size,
    required this.at,
    required this.text,
    super.by,
    super.seq,
  });

  /// Font size in page units (the page is 9000 high).
  final int size;

  /// The text's top-right corner. The text runs in its own direction and is right-aligned here.
  final BoardPoint at;
  final String text;

  @override
  Json toInputJson() => {
    'kind': 'text',
    'id': id,
    'pageId': pageId,
    'color': color,
    'size': size,
    'at': _pointJson(at),
    'text': text,
  };
}

/// A live preview batch of an in-progress stroke, or a laser trail. Relayed, never stored.
class BoardProgress {
  const BoardProgress({
    required this.strokeId,
    required this.pageId,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    required this.done,
  });

  factory BoardProgress.fromJson(Json j) => BoardProgress(
    strokeId: j['strokeId'] as String,
    pageId: j['pageId'] as String,
    tool: j['tool'] as String,
    color: j['color'] as String,
    width: j['width'] as int,
    points: listOf<int>(j['points']),
    done: j['done'] as bool,
  );

  final String strokeId;
  final String pageId;

  /// A [PenTool] wire name, or `laser`.
  final String tool;
  final String color;
  final int width;
  final List<int> points;
  final bool done;

  bool get isLaser => tool == 'laser';

  Json toJson() => {
    'type': 'wb.progress',
    'strokeId': strokeId,
    'pageId': pageId,
    'tool': tool,
    'color': color,
    'width': width,
    'points': points,
    'done': done,
  };
}

class BoardSnapshot {
  const BoardSnapshot({
    required this.pages,
    required this.activePageId,
    required this.items,
  });

  factory BoardSnapshot.fromJson(Json j) => BoardSnapshot(
    pages: [for (final p in asJsonList(j['pages'])) BoardPage.fromJson(p)],
    activePageId: j['activePageId'] as String,
    items: [for (final i in asJsonList(j['items'])) BoardItem.fromJson(i)],
  );

  final List<BoardPage> pages;
  final String activePageId;
  final List<BoardItem> items;

  Json toJson() => {
    'pages': [for (final p in pages) p.toJson()],
    'activePageId': activePageId,
    'items': [for (final i in items) i.toJson()],
  };
}
