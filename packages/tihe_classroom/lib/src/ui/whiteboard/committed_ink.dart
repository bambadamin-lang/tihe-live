import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'board_painter.dart';

/// The board's finished ink, kept as an image between frames.
///
/// Impeller — the renderer on iOS, Android, macOS and the desktops — keeps nothing from one
/// frame to the next: a RepaintBoundary saves recording a layer again, not rasterising it
/// again. A page of finished strokes was tessellated and filled anew on every frame the window
/// drew — at the display's rate while a remote stroke glides in — and the cost grew with every
/// stroke of the lesson. Here the finished ink is drawn into an image when it changes, and each
/// frame draws that one image.
///
/// The image is made for the board's exact place on the screen's pixel grid and drawn without
/// resampling, so it is pixel for pixel what drawing the strokes would give. While the board
/// moves or resizes (a layout change, maximise, its arrival) the strokes are drawn directly,
/// and a new image is made once it holds still.
class CommittedInk extends LeafRenderObjectWidget {
  const CommittedInk({
    super.key,
    required this.painter,
    required this.devicePixelRatio,
  });

  /// Draws the finished layer ([BoardLayer.committed]).
  final BoardPainter painter;
  final double devicePixelRatio;

  @override
  RenderCommittedInk createRenderObject(BuildContext context) =>
      RenderCommittedInk(painter, devicePixelRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCommittedInk renderObject,
  ) => renderObject
    ..painter = painter
    ..devicePixelRatio = devicePixelRatio;
}

/// Where the board sits on the screen's pixel grid: its size, its scale to physical pixels and
/// how far its top-left corner is past a whole pixel.
typedef _Placement = ({Size size, double scale, double dx, double dy});

bool _same(_Placement? a, _Placement? b) =>
    a != null &&
    b != null &&
    a.size == b.size &&
    (a.scale - b.scale).abs() < 1e-6 &&
    (a.dx - b.dx).abs() < 1e-3 &&
    (a.dy - b.dy).abs() < 1e-3;

class RenderCommittedInk extends RenderBox {
  RenderCommittedInk(this._painter, this._devicePixelRatio);

  /// Larger than this on a side, the strokes are always drawn directly.
  static const maxImageSide = 8192;

  BoardPainter _painter;
  BoardPainter get painter => _painter;
  set painter(BoardPainter value) {
    if (identical(value, _painter)) return;
    final changed = value.shouldRepaint(_painter);
    _painter = value;
    if (changed) _forgetImage();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _forgetImage();
  }

  ui.Image? _image;
  _Placement? _imagePlacement;

  /// Where the board was when last painted or checked.
  _Placement? _seen;
  bool _checking = false;

  /// Whether the last paint used the image — for tests.
  @visibleForTesting
  bool get showingImage => _showingImage;
  bool _showingImage = false;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  // As a CustomPaint without a hit test of its own: the whole board is a target.
  @override
  bool hitTestSelf(Offset position) => true;

  void _forgetImage() {
    _image?.dispose();
    _image = null;
    _imagePlacement = null;
    markNeedsPaint();
  }

  /// Null when the board is rotated, skewed or squashed: then pixels cannot line up.
  _Placement? _placement() {
    if (!hasSize || size.isEmpty) return null;
    final m = getTransformTo(null).storage;
    final plain =
        m[1] == 0 &&
        m[2] == 0 &&
        m[3] == 0 &&
        m[4] == 0 &&
        m[6] == 0 &&
        m[7] == 0 &&
        m[8] == 0 &&
        m[9] == 0 &&
        m[11] == 0 &&
        m[15] == 1 &&
        m[0] == m[5] &&
        m[0] > 0;
    if (!plain) return null;
    final scale = m[0] * _devicePixelRatio;
    if (size.width * scale + 1 > maxImageSide ||
        size.height * scale + 1 > maxImageSide) {
      return null;
    }
    final x = m[12] * _devicePixelRatio, y = m[13] * _devicePixelRatio;
    return (
      size: size,
      scale: scale,
      dx: x - x.floorToDouble(),
      dy: y - y.floorToDouble(),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // A repaint boundary paints at its own origin; anything else could not be placed.
    assert(offset == Offset.zero);
    final placement = _placement();
    final still = _same(placement, _seen);
    _seen = placement;
    _checkAfterFrame();
    final canvas = context.canvas;
    if (placement != null && (still || _same(placement, _imagePlacement))) {
      if (!_same(placement, _imagePlacement)) {
        _image?.dispose();
        _image = _render(placement);
        _imagePlacement = placement;
      }
      // Back onto the pixel grid, at one image pixel per screen pixel: no resampling.
      canvas
        ..save()
        ..translate(
          -placement.dx / placement.scale,
          -placement.dy / placement.scale,
        )
        ..scale(1 / placement.scale)
        ..drawImage(
          _image!,
          Offset.zero,
          Paint()..filterQuality = FilterQuality.none,
        )
        ..restore();
      _showingImage = true;
    } else {
      _painter.paint(canvas, size);
      _showingImage = false;
    }
  }

  ui.Image _render(_Placement p) {
    final recorder = ui.PictureRecorder();
    _painter.paint(
      Canvas(recorder)
        ..translate(p.dx, p.dy)
        ..scale(p.scale),
      p.size,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (p.dx + p.size.width * p.scale).ceil(),
      (p.dy + p.size.height * p.scale).ceil(),
    );
    picture.dispose();
    return image;
  }

  /// After every frame, sees whether the board has moved without being painted (a pod gliding
  /// to a new place moves its layer, not its content). Moving, or come to rest drawing the
  /// strokes directly, it is painted again — into an image once it holds still. Runs only on
  /// frames the window draws anyway; it never asks for one by itself unless something changed.
  void _checkAfterFrame() {
    if (_checking) return;
    _checking = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checking = false;
      if (!attached) return;
      final placement = _placement();
      final moved = !_same(placement, _seen);
      final settledWithoutImage =
          !moved && placement != null && !_same(placement, _imagePlacement);
      if (moved || settledWithoutImage) {
        _seen = moved ? placement : _seen;
        markNeedsPaint();
      } else {
        _checkAfterFrame();
      }
    }, debugLabel: 'CommittedInk.check');
  }

  @override
  void detach() {
    // Off screen, the image is only memory.
    _image?.dispose();
    _image = null;
    _imagePlacement = null;
    _seen = null;
    super.detach();
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
