import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The TIHE pointer: a navy arrow with a glowing blue rim, the brand's cursor on every screen.
///
/// Flutter's framework only knows system cursors, so this is a [MouseCursor] of its own:
///
/// - **Windows**: a real system cursor. The Windows embedder accepts a BGRA bitmap on
///   `flutter/mousecursor` (`createCustomCursor/windows`), so the arrow is drawn once per
///   display scale and handed to the OS — it moves with the hardware, with no frame of lag.
/// - **macOS and Linux**: the embedders have no such call, so the system cursor is hidden and
///   the arrow is drawn over the app by a [GlowCursorScope] at the root. Without a scope there
///   is nothing to draw it, and the plain system arrow is used instead.
/// - **Everywhere else** (touch, web, tests): the matching system cursor.
///
/// Text fields keep the system I-beam and the whiteboard its crosshair: those shapes carry
/// meaning an arrow cannot.
enum GlowCursorKind { basic, click }

/// The cursor for anything clickable ([click]) and for everything else ([basic]).
abstract final class GlowCursors {
  static const basic = GlowCursor._(
    GlowCursorKind.basic,
    SystemMouseCursors.basic,
  );

  /// Brighter, so a control under the pointer reads as live before it is hovered.
  static const click = GlowCursor._(
    GlowCursorKind.click,
    SystemMouseCursors.click,
  );
}

class GlowCursor extends MouseCursor {
  const GlowCursor._(this.kind, this.fallback);

  final GlowCursorKind kind;

  /// Shown where the arrow cannot be.
  final SystemMouseCursor fallback;

  @override
  MouseCursorSession createSession(int device) =>
      _GlowCursorSession(this, device);

  @override
  String get debugDescription => 'GlowCursor(${kind.name})';
}

class _GlowCursorSession extends MouseCursorSession {
  _GlowCursorSession(GlowCursor super.cursor, super.device);

  bool disposed = false;

  GlowCursor get glow => cursor as GlowCursor;

  @override
  Future<void> activate() => GlowCursorEngine.instance._activate(this);

  @override
  void dispose() {
    disposed = true;
    GlowCursorEngine.instance._deactivate(this);
  }
}

/// How the arrow is shown on this platform.
enum GlowCursorMode { native, overlay, system }

/// Shows [GlowCursor]s: creates the Windows cursors, drives the overlay elsewhere.
class GlowCursorEngine {
  GlowCursorEngine._();

  static final instance = GlowCursorEngine._();

  /// Forces a mode, for tests.
  @visibleForTesting
  static GlowCursorMode? debugModeOverride;

  static const _channel = SystemChannels.mouseCursor;

  /// The arrow the overlay should draw, or null when the pointer shows something else.
  final ValueNotifier<GlowCursorKind?> overlayKind = ValueNotifier(null);

  int _painters = 0;
  bool _nativeFailed = false;
  _GlowCursorSession? _current;

  /// Cursors already handed to Windows, by name.
  final Map<String, Future<bool>> _created = {};

  GlowCursorMode get mode {
    final forced = debugModeOverride;
    if (forced != null) return forced;
    final overlay = _painters > 0
        ? GlowCursorMode.overlay
        : GlowCursorMode.system;
    if (kIsWeb) return GlowCursorMode.system;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => _nativeFailed ? overlay : GlowCursorMode.native,
      TargetPlatform.macOS || TargetPlatform.linux => overlay,
      _ => GlowCursorMode.system,
    };
  }

  @visibleForTesting
  void debugReset() {
    _created.clear();
    _nativeFailed = false;
    _current = null;
    overlayKind.value = null;
  }

  Future<void> _activate(_GlowCursorSession session) async {
    _current = session;
    final kind = session.glow.kind;
    switch (mode) {
      case GlowCursorMode.native:
        final name = await _native(kind, _devicePixelRatio);
        if (session.disposed) return;
        if (name != null) {
          await _invoke('setCustomCursor/windows', {'name': name});
          return;
        }
        // The engine refused the bitmap: never try again this run.
        _nativeFailed = true;
        return _activate(session);
      case GlowCursorMode.overlay:
        overlayKind.value = kind;
        await _system(session.device, 'none');
      case GlowCursorMode.system:
        await _system(session.device, session.glow.fallback.kind);
    }
  }

  void _deactivate(_GlowCursorSession session) {
    if (_current != session) return;
    _current = null;
    overlayKind.value = null;
  }

  double get _devicePixelRatio {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final view = dispatcher.implicitView ?? dispatcher.views.firstOrNull;
    return view?.devicePixelRatio ?? 1;
  }

  /// The name of the Windows cursor for [kind] at [scale], creating it the first time.
  Future<String?> _native(GlowCursorKind kind, double scale) async {
    final name = 'tihe-glow-${kind.name}@${scale.toStringAsFixed(2)}';
    final ok = await (_created[name] ??= _create(name, kind, scale));
    return ok ? name : null;
  }

  Future<bool> _create(String name, GlowCursorKind kind, double scale) async {
    try {
      final bitmap = await GlowCursorArt.bitmap(kind, scale);
      await _channel.invokeMethod<Object?>('createCustomCursor/windows', {
        'name': name,
        'buffer': bitmap.bgra,
        'width': bitmap.width,
        'height': bitmap.height,
        // The embedder reads these as doubles, and would reject an int.
        'hotX': bitmap.hotSpot.dx.toDouble(),
        'hotY': bitmap.hotSpot.dy.toDouble(),
      });
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _system(int device, String kind) =>
      _invoke('activateSystemCursor', {'device': device, 'kind': kind});

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on Object {
      // No cursor channel (tests, a headless embedder): the pointer keeps whatever it had.
    }
  }
}

/// The arrow for a native cursor: straight-alpha BGRA rows, top to bottom.
@immutable
class GlowCursorBitmap {
  const GlowCursorBitmap({
    required this.bgra,
    required this.width,
    required this.height,
    required this.hotSpot,
  });

  final Uint8List bgra;
  final int width;
  final int height;

  /// The arrow's tip, in physical pixels from the top left.
  final Offset hotSpot;
}

/// The drawing of the arrow, shared by the native cursor and the overlay so both look the same.
abstract final class GlowCursorArt {
  /// The whole drawing, glow included, in logical pixels.
  static const size = Size(32, 38);

  /// Where the tip is: the point that clicks.
  static const hotSpot = Offset(7.4, 7.8);

  static const _unit = 19.0;
  static const _origin = Offset(7, 7);

  // The outline, tip first, in units of the left edge's length. The tail runs parallel to
  // itself and the left edge leans a little, as in the brand drawing.
  static const _outline = [
    Offset(0, 0),
    Offset(0.06, 1),
    Offset(0.33, 0.8),
    Offset(0.56, 1.17),
    Offset(0.72, 1.07),
    Offset(0.5, 0.71),
    Offset(0.86, 0.64),
  ];

  // Corner radii, in logical pixels: a sharp-ish tip, soft outer corners, tight notches.
  static const _radii = [0.7, 1.6, 1.0, 1.6, 1.6, 1.0, 1.6];

  static final Path _path = _rounded([
    for (final p in _outline) _origin + p * _unit,
  ], _radii);

  /// Paints the arrow with its tip at [hotSpot], in logical pixels.
  static void paint(Canvas canvas, GlowCursorKind kind) {
    final click = kind == GlowCursorKind.click;
    final bounds = _path.getBounds();

    // The glow: a wide soft halo and a tight bright one.
    canvas
      ..drawPath(
        _path,
        Paint()
          ..color = const Color(0xFF2F6FFE).withValues(alpha: click ? 0.7 : 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
      )
      ..drawPath(
        _path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(
            0xFF3D8BFF,
          ).withValues(alpha: click ? 0.85 : 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
      );

    // The body: deep navy, lit towards the tip.
    canvas.drawPath(
      _path,
      Paint()
        ..shader = ui.Gradient.linear(
          bounds.topLeft,
          bounds.bottomRight,
          click
              ? const [Color(0xFF2A57D6), Color(0xFF10227A), Color(0xFF0A1446)]
              : const [Color(0xFF1D43B8), Color(0xFF0C1A5A), Color(0xFF070F34)],
          const [0, 0.55, 1],
        ),
    );

    // Light caught inside the rim, and a sheen along the upper edge.
    canvas
      ..save()
      ..clipPath(_path)
      ..drawPath(
        _path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF5B9BFF).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      )
      ..drawLine(
        _origin + const Offset(0.1, 0.16) * _unit,
        _origin + const Offset(0.68, 0.6) * _unit,
        Paint()
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.1),
      )
      ..restore();

    // The rim: ice blue at the tip, electric blue at the tail.
    canvas.drawPath(
      _path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeJoin = StrokeJoin.round
        ..shader = ui.Gradient.linear(
          bounds.topLeft,
          bounds.bottomRight,
          click
              ? const [Color(0xFFD2F1FF), Color(0xFF6DB6FF), Color(0xFF3D7BFF)]
              : const [Color(0xFFA5E0FF), Color(0xFF4A9BFF), Color(0xFF2F63FF)],
          const [0, 0.5, 1],
        ),
    );
  }

  /// The arrow rasterised at [scale] physical pixels per logical pixel.
  static Future<GlowCursorBitmap> bitmap(
    GlowCursorKind kind,
    double scale,
  ) async {
    final width = (size.width * scale).ceil();
    final height = (size.height * scale).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    paint(canvas, kind);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    try {
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) throw StateError('cursor image has no pixels');
      final bgra = Uint8List.fromList(data.buffer.asUint8List());
      for (var i = 0; i < bgra.length; i += 4) {
        final r = bgra[i];
        bgra[i] = bgra[i + 2];
        bgra[i + 2] = r;
        // Windows masks out opaque pure black, which the arrow never uses; nudge any the
        // antialiasing produced so no pixel of the glow is punched out.
        if (bgra[i] == 0 &&
            bgra[i + 1] == 0 &&
            bgra[i + 2] == 0 &&
            bgra[i + 3] > 0) {
          bgra[i] = 1;
        }
      }
      return GlowCursorBitmap(
        bgra: bgra,
        width: width,
        height: height,
        hotSpot: hotSpot * scale,
      );
    } finally {
      image.dispose();
    }
  }

  /// A closed polygon with each corner rounded by its own radius.
  static Path _rounded(List<Offset> points, List<double> radii) {
    final path = Path();
    final n = points.length;
    for (var i = 0; i < n; i++) {
      final prev = points[(i - 1 + n) % n];
      final at = points[i];
      final next = points[(i + 1) % n];
      final toPrev = prev - at;
      final toNext = next - at;
      final r = radii[i];
      final a = at + toPrev / toPrev.distance * r;
      final b = at + toNext / toNext.distance * r;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.quadraticBezierTo(at.dx, at.dy, b.dx, b.dy);
    }
    return path..close();
  }
}

/// Gives everything below it the glow cursor, and — on macOS and Linux — draws it.
///
/// Put one at the root of the app (`MaterialApp.builder`), so dialogs and menus are covered too.
/// A nested scope only sets the cursor; the root one does the drawing.
class GlowCursorScope extends StatefulWidget {
  const GlowCursorScope({super.key, required this.child});

  final Widget child;

  @override
  State<GlowCursorScope> createState() => _GlowCursorScopeState();
}

class _GlowCursorScopeMarker extends InheritedWidget {
  const _GlowCursorScopeMarker({required super.child});

  @override
  bool updateShouldNotify(_GlowCursorScopeMarker old) => false;
}

class _GlowCursorScopeState extends State<GlowCursorScope> {
  final _position = ValueNotifier<Offset?>(null);
  bool? _paints;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_paints != null) return;
    _paints =
        context.getInheritedWidgetOfExactType<_GlowCursorScopeMarker>() == null;
    if (_paints!) GlowCursorEngine.instance._painters++;
  }

  @override
  void dispose() {
    if (_paints ?? false) GlowCursorEngine.instance._painters--;
    _position.dispose();
    super.dispose();
  }

  void _track(PointerEvent e) {
    if (e.kind == ui.PointerDeviceKind.mouse) _position.value = e.localPosition;
  }

  @override
  Widget build(BuildContext context) {
    final region = MouseRegion(cursor: GlowCursors.basic, child: widget.child);
    if (!(_paints ?? false)) return region;
    return _GlowCursorScopeMarker(
      child: MouseRegion(
        onHover: _track,
        onExit: (_) => _position.value = null,
        child: Listener(
          onPointerMove: _track,
          onPointerDown: _track,
          behavior: HitTestBehavior.translucent,
          // Positions here are physical: the scope works above any Directionality.
          child: Stack(
            alignment: Alignment.topLeft,
            textDirection: TextDirection.ltr,
            children: [
              region,
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _OverlayPainter(
                        _position,
                        GlowCursorEngine.instance.overlayKind,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.position, this.kind)
    : super(repaint: Listenable.merge([position, kind]));

  final ValueListenable<Offset?> position;
  final ValueListenable<GlowCursorKind?> kind;

  @override
  void paint(Canvas canvas, Size size) {
    final at = position.value;
    final shown = kind.value;
    if (at == null || shown == null) return;
    if (GlowCursorEngine.instance.mode != GlowCursorMode.overlay) return;
    canvas
      ..save()
      ..translate(
        at.dx - GlowCursorArt.hotSpot.dx,
        at.dy - GlowCursorArt.hotSpot.dy,
      );
    GlowCursorArt.paint(canvas, shown);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.position != position || old.kind != kind;
}
