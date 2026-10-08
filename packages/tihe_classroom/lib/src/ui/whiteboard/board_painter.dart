import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import '../../contracts.dart';
import '../../domain/board_model.dart';
import '../../state/board_controller.dart';
import '../../state/classroom_session.dart';

/// Which part of a page a [BoardPainter] draws.
///
/// The board is two layers on screen: [committed] (background and finished items, repainted
/// only when they change) under [live] (other people's strokes in progress, your draft and
/// the laser, repainted every frame while something moves). Drawing a stroke then costs one
/// stroke per frame, not the whole page.
enum BoardLayer { all, committed, live }

/// Paints one whiteboard page. The same drawing rules as the Egress template
/// (services/live/egress-template/src/board.ts): same pen styles, backgrounds and paint order,
/// so the recording shows what the class saw.
class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.page,
    required this.items,
    required this.hidden,
    required this.previews,
    required this.draft,
    required this.now,
    required this.fontFamily,
    this.layer = BoardLayer.all,
    super.repaint,
  });

  final BoardLayer layer;

  final BoardPage page;

  /// Items on this page, in paint (sequence) order.
  final List<BoardItem> items;

  /// Being erased right now: not drawn.
  final Set<String> hidden;
  final List<RemotePreview> previews;
  final Draft? draft;
  final DateTime now;
  final String fontFamily;

  static const laserFade = Duration(milliseconds: 1200);

  /// Outlines and laid-out text of finished items, worked out once per item. Items are
  /// immutable, and running perfect-freehand is the costliest step in painting a page: without
  /// these, every repaint of the finished layer — each stroke anyone adds — redid every stroke
  /// on the page.
  static final _outlines = Expando<Path>('board outlines');
  static final _texts = Expando<(String, TextPainter)>('board texts');

  /// The outline of a finished [stroke], from the cache when it has been drawn before.
  static Path outlineOf(StrokeItem stroke) =>
      _outlines[stroke] ??= outline(stroke.points, stroke.width, stroke.tool);

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = BoardViewport(size);
    canvas.save();
    canvas.clipRect(viewport.page);
    canvas.translate(viewport.page.left, viewport.page.top);
    canvas.scale(viewport.scale);

    if (layer != BoardLayer.live) {
      _background(canvas);
      final visible = items.where((i) => !hidden.contains(i.id)).toList();
      bool underlay(BoardItem i) =>
          i is StrokeItem && penStyles[i.tool]!.underlay;
      for (final item in visible.where(underlay)) {
        _item(canvas, item);
      }
      for (final item in visible.where((i) => !underlay(i))) {
        _item(canvas, item);
      }
    }
    if (layer != BoardLayer.committed) {
      for (final p in previews.where((p) => p.pageId == page.id)) {
        if (p.isLaser) {
          _laser(
            canvas,
            p.points,
            p.color,
            p.width,
            now.difference(p.updatedAt),
          );
        } else {
          final points = p.revealedAt(now);
          if (points.length >= 2) {
            _pen(canvas, PenTool.fromWire(p.tool), p.color, p.width, points);
          }
        }
      }
      final d = draft;
      if (d != null && d.pageId == page.id) _draft(canvas, d);
    }
    canvas.restore();
  }

  void _background(Canvas canvas) {
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

  void _pen(
    Canvas canvas,
    PenTool tool,
    String color,
    int width,
    List<int> points, {
    StrokeItem? finished,
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
    } else {
      // Ink still being drawn changes every frame, so only finished strokes are cached.
      canvas.drawPath(
        finished != null ? outlineOf(finished) : outline(points, width, tool),
        paint,
      );
    }
  }

  void _shape(
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

  void _text(Canvas canvas, TextItem item) {
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

  void _item(Canvas canvas, BoardItem item) {
    switch (item) {
      case StrokeItem(:final tool, :final color, :final width, :final points):
        _pen(canvas, tool, color, width, points, finished: item);
      case ShapeItem(
        :final shape,
        :final color,
        :final width,
        :final fill,
        :final from,
        :final to,
      ):
        _shape(canvas, shape, color, width, fill, from, to);
      case TextItem():
        _text(canvas, item);
    }
  }

  void _laser(
    Canvas canvas,
    List<int> points,
    String color,
    int width,
    Duration age,
  ) {
    final fade =
        1 - (age.inMilliseconds / laserFade.inMilliseconds).clamp(0.0, 1.0);
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

  void _draft(Canvas canvas, Draft d) {
    final pen = d.tool.penTool;
    final shape = d.tool.shapeKind;
    if (pen != null) {
      _pen(canvas, pen, d.color, d.width, d.points);
    } else if (shape != null) {
      _shape(
        canvas,
        shape,
        d.color,
        d.width,
        d.fill,
        (x: d.points[0], y: d.points[1]),
        (x: d.points[2], y: d.points[3]),
      );
    } else if (d.tool == BoardTool.laser) {
      _laser(canvas, d.points, d.color, d.width, Duration.zero);
    }
  }

  @override
  bool shouldRepaint(BoardPainter old) {
    // Items are immutable and reused between rebuilds, so comparing the lists element by
    // element is cheap and keeps the committed layer still while a stroke is being drawn.
    bool committedChanged() =>
        old.page != page ||
        old.fontFamily != fontFamily ||
        !listEquals(old.items, items) ||
        !setEquals(old.hidden, hidden);
    bool liveChanged() =>
        old.page != page ||
        !identical(old.previews, previews) ||
        old.draft != draft ||
        old.now != now;
    return old.layer != layer ||
        switch (layer) {
          BoardLayer.committed => committedChanged(),
          BoardLayer.live => liveChanged(),
          BoardLayer.all => committedChanged() || liveChanged(),
        };
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
