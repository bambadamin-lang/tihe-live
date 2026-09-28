import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import '../../contracts.dart';
import '../../domain/board_model.dart';
import '../../state/board_controller.dart';
import '../../state/classroom_session.dart';

/// Paints one whiteboard page. The same drawing rules as the Egress template
/// (services/live/egress-template/src/board.ts): same pen styles, backgrounds and paint order,
/// so the recording shows what the class saw.
///
/// Two layers. [BoardPainter] draws the page and its committed items, and repaints only when
/// those change. [BoardLivePainter] draws what is still moving — other people's strokes as they
/// draw them, your own draft, the laser — and repaints at the rate they arrive. A stroke being
/// drawn by someone else no longer repaints every item on the board 30 times a second.
///
/// Committed items are immutable, so the expensive parts of drawing them — a pen stroke's
/// perfect-freehand outline, a text item's shaped layout — are computed once per item and kept
/// with it.
class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.page,
    required this.items,
    required this.hidden,
    required this.fontFamily,
  });

  final BoardPage page;

  /// Items on this page, in paint (sequence) order.
  final List<BoardItem> items;

  /// Being erased right now: not drawn. A snapshot, so a change is seen.
  final Set<String> hidden;
  final String fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = _Ink(fontFamily);
    _enterPage(canvas, size);
    ink.background(canvas, page);
    final visible = items.where((i) => !hidden.contains(i.id)).toList();
    bool underlay(BoardItem i) =>
        i is StrokeItem && penStyles[i.tool]!.underlay;
    for (final item in visible.where(underlay)) {
      ink.item(canvas, item);
    }
    for (final item in visible.where((i) => !underlay(i))) {
      ink.item(canvas, item);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.page != page ||
      old.fontFamily != fontFamily ||
      !listEquals(old.items, items) ||
      !setEquals(old.hidden, hidden);

  /// A committed stroke's outline, for hit-testing and painting alike.
  static Path outline(List<int> points, int width, PenTool tool) =>
      _Ink.outline(points, width, tool);
}

/// The moving part of the board, over [BoardPainter]: remote previews, the local draft, the laser.
class BoardLivePainter extends CustomPainter {
  BoardLivePainter({
    required this.page,
    required this.previews,
    required this.draft,
    required this.now,
    required this.fontFamily,
  });

  final BoardPage page;
  final List<RemotePreview> previews;
  final Draft? draft;
  final DateTime now;
  final String fontFamily;

  static const laserFade = Duration(milliseconds: 1200);

  @override
  void paint(Canvas canvas, Size size) {
    final onPage = previews.where((p) => p.pageId == page.id);
    final d = draft;
    if (onPage.isEmpty && (d == null || d.pageId != page.id)) return;
    final ink = _Ink(fontFamily);
    _enterPage(canvas, size);
    for (final p in onPage) {
      if (p.isLaser) {
        ink.laser(
          canvas,
          p.points,
          p.color,
          p.width,
          now.difference(p.updatedAt),
        );
      } else {
        ink.pen(canvas, PenTool.fromWire(p.tool), p.color, p.width, p.points);
      }
    }
    if (d != null && d.pageId == page.id) ink.draft(canvas, d);
    canvas.restore();
  }

  @override
  bool shouldRepaint(BoardLivePainter old) =>
      old.page != page ||
      !identical(old.previews, previews) ||
      old.draft != draft ||
      old.now != now;
}

void _enterPage(Canvas canvas, Size size) {
  final viewport = BoardViewport(size);
  canvas.save();
  canvas.clipRect(viewport.page);
  canvas.translate(viewport.page.left, viewport.page.top);
  canvas.scale(viewport.scale);
}

/// The drawing rules, shared by both layers.
class _Ink {
  _Ink(this.fontFamily);

  final String fontFamily;

  /// Per committed item, computed once. An Expando lets them go with their item.
  static final _outlines = Expando<Path>('stroke outline');
  static final _texts = Expando<(String, TextPainter)>('text layout');

  void background(Canvas canvas, BoardPage page) {
    const rect = Rect.fromLTWH(0, 0, boardWidth + 0.0, boardHeight + 0.0);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFBFBF7));
    final line = Paint()
      ..color = const Color(0x29506EA0)
      ..strokeWidth = 8;
    switch (page.background) {
      case BoardBackground.grid:
        for (var x = 500.0; x < boardWidth; x += 500) {
          canvas.drawLine(Offset(x, 0), Offset(x, boardHeight + 0.0), line);
        }
        for (var y = 500.0; y < boardHeight; y += 500) {
          canvas.drawLine(Offset(0, y), Offset(boardWidth + 0.0, y), line);
        }
      case BoardBackground.lines:
        for (var y = 600.0; y < boardHeight; y += 450) {
          canvas.drawLine(Offset(0, y), Offset(boardWidth + 0.0, y), line);
        }
      case BoardBackground.dots:
        final dot = Paint()..color = const Color(0x47506EA0);
        for (var x = 500.0; x < boardWidth; x += 500) {
          for (var y = 500.0; y < boardHeight; y += 500) {
            canvas.drawRect(
              Rect.fromCenter(center: Offset(x, y), width: 24, height: 24),
              dot,
            );
          }
        }
      case BoardBackground.plain:
        break;
    }
  }

  static Path outline(List<int> points, int width, PenTool tool) {
    final style = penStyles[tool]!;
    final vectors = [
      for (var i = 0; i + 1 < points.length; i += 2)
        PointVector(points[i].toDouble(), points[i + 1].toDouble()),
    ];
    final outline = getStroke(
      vectors,
      options: StrokeOptions(
        size: width.toDouble(),
        thinning: style.thinning,
        smoothing: style.smoothing,
        streamline: style.streamline,
        simulatePressure: style.simulatePressure,
        isComplete: true,
      ),
    );
    final path = Path();
    if (outline.isEmpty) return path;
    path.moveTo(outline.first.dx, outline.first.dy);
    // Quadratic curves through midpoints, as perfect-freehand's own SVG helper does.
    for (var i = 1; i < outline.length; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    }
    return path..close();
  }

  void pen(
    Canvas canvas,
    PenTool tool,
    String color,
    int width,
    List<int> points, {
    Object? cacheKey,
  }) {
    final style = penStyles[tool]!;
    final paint = Paint()
      ..color = colorFromHex(color).withValues(alpha: style.opacity)
      ..blendMode = style.underlay ? BlendMode.multiply : BlendMode.srcOver;
    if (points.length == 2) {
      canvas.drawCircle(
        Offset(points[0] + 0.0, points[1] + 0.0),
        width / 2,
        paint,
      );
    } else if (cacheKey != null) {
      canvas.drawPath(
        _outlines[cacheKey] ??= outline(points, width, tool),
        paint,
      );
    } else {
      canvas.drawPath(outline(points, width, tool), paint);
    }
  }

  void shape(
    Canvas canvas,
    ShapeKind shape,
    String color,
    int width,
    String? fill,
    BoardPoint from,
    BoardPoint to,
  ) {
    final stroke = Paint()
      ..color = colorFromHex(color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width.toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final a = Offset(from.x + 0.0, from.y + 0.0);
    final b = Offset(to.x + 0.0, to.y + 0.0);
    final rect = Rect.fromPoints(a, b);
    switch (shape) {
      case ShapeKind.rect || ShapeKind.ellipse:
        final isRect = shape == ShapeKind.rect;
        if (fill != null) {
          final paint = Paint()..color = colorFromHex(fill);
          isRect ? canvas.drawRect(rect, paint) : canvas.drawOval(rect, paint);
        }
        isRect ? canvas.drawRect(rect, stroke) : canvas.drawOval(rect, stroke);
      case ShapeKind.line || ShapeKind.arrow:
        canvas.drawLine(a, b, stroke);
        if (shape == ShapeKind.arrow) {
          final angle = atan2(b.dy - a.dy, b.dx - a.dx);
          final head = max(width * 4.0, 180.0);
          canvas.drawLine(
            b,
            b - Offset(cos(angle - 0.5), sin(angle - 0.5)) * head,
            stroke,
          );
          canvas.drawLine(
            b,
            b - Offset(cos(angle + 0.5), sin(angle + 0.5)) * head,
            stroke,
          );
        }
    }
  }

  void text(Canvas canvas, TextItem item) {
    final cached = _texts[item];
    final painter = cached != null && cached.$1 == fontFamily
        ? cached.$2
        : _layoutText(item);
    // `at` is the text's top-right corner, whatever its direction.
    painter.paint(canvas, Offset(item.at.x - painter.width, item.at.y + 0.0));
  }

  TextPainter _layoutText(TextItem item) {
    final painter = TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(
          color: colorFromHex(item.color),
          fontSize: item.size.toDouble(),
          fontFamily: fontFamily,
          fontFamilyFallback: const ['Vazirmatn', 'Noto Sans Arabic', 'Tahoma'],
          height: 1.4,
        ),
      ),
      // A formula reads left to right even on a Persian board; the text's first strong
      // character decides, as it would in a word processor.
      textDirection: textDirectionOf(item.text),
      textAlign: TextAlign.right,
    )..layout();
    _texts[item] = (fontFamily, painter);
    return painter;
  }

  void item(Canvas canvas, BoardItem item) {
    switch (item) {
      case StrokeItem(:final tool, :final color, :final width, :final points):
        pen(canvas, tool, color, width, points, cacheKey: item);
      case ShapeItem(
        :final shape,
        :final color,
        :final width,
        :final fill,
        :final from,
        :final to,
      ):
        this.shape(canvas, shape, color, width, fill, from, to);
      case TextItem():
        text(canvas, item);
    }
  }

  void laser(
    Canvas canvas,
    List<int> points,
    String color,
    int width,
    Duration age,
  ) {
    final fade =
        1 -
        (age.inMilliseconds / BoardLivePainter.laserFade.inMilliseconds).clamp(
          0.0,
          1.0,
        );
    if (fade <= 0 || points.length < 2) return;
    final path = Path()..moveTo(points[0] + 0.0, points[1] + 0.0);
    for (var i = 2; i + 1 < points.length; i += 2) {
      path.lineTo(points[i] + 0.0, points[i + 1] + 0.0);
    }
    final c = colorFromHex(color);
    canvas.drawPath(
      path,
      Paint()
        ..color = c.withValues(alpha: 0.35 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = c.withValues(alpha: fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width.toDouble()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void draft(Canvas canvas, Draft d) {
    final pen = d.tool.penTool;
    final shape = d.tool.shapeKind;
    if (pen != null) {
      this.pen(canvas, pen, d.color, d.width, d.points);
    } else if (shape != null) {
      this.shape(
        canvas,
        shape,
        d.color,
        d.width,
        d.fill,
        (x: d.points[0], y: d.points[1]),
        (x: d.points[2], y: d.points[3]),
      );
    } else if (d.tool == BoardTool.laser) {
      laser(canvas, d.points, d.color, d.width, Duration.zero);
    }
  }
}

final _rtlChar = RegExp('[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final _ltrChar = RegExp('[A-Za-z\u00C0-\u024F]');

/// The direction of a piece of text from its first strong character (RTL when there is none).
TextDirection textDirectionOf(String text) {
  for (final ch in text.characters) {
    if (_rtlChar.hasMatch(ch)) return TextDirection.rtl;
    if (_ltrChar.hasMatch(ch)) return TextDirection.ltr;
  }
  return TextDirection.rtl;
}

/// Renders a page to an image — used by tests and by thumbnails in the page strip.
Future<ui.Image> renderBoardImage(BoardPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  return recorder.endRecording().toImage(
    size.width.round(),
    size.height.round(),
  );
}
