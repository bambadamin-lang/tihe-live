import 'dart:ui';

import '../contracts.dart';

/// Where each pod goes on screen (docs/11 §5).
///
/// Wide screens show the layout's 12 × 12 grid, measured from the start edge — so in RTL the
/// grid's column 0 is on the right. Narrow screens (phones) show one pod at a time: the
/// layout's primary pod, with the others behind tabs.
abstract final class StageGeometry {
  /// Below this width the stage switches to one-pod-at-a-time.
  static const compactWidth = 600.0;

  static bool isCompact(Size size) => size.width < compactWidth;

  static Map<String, Rect> grid(
    Layout layout,
    Size size, {
    required TextDirection direction,
    double gap = 12,
  }) {
    final cellW = size.width / layoutGrid;
    final cellH = size.height / layoutGrid;
    final half = gap / 2;
    return {
      for (final p in layout.pods)
        p.id: Rect.fromLTWH(
          (direction == TextDirection.rtl ? layoutGrid - p.x - p.w : p.x) *
                  cellW +
              half,
          p.y * cellH + half,
          p.w * cellW - gap,
          p.h * cellH - gap,
        ),
    };
  }

  /// Screen, then whiteboard, then speaker, then gallery — what matters most on a phone.
  static const _priority = [
    PodKind.screen,
    PodKind.whiteboard,
    PodKind.speaker,
    PodKind.gallery,
    PodKind.hands,
    PodKind.chat,
    PodKind.participants,
  ];

  /// The pod a phone shows first: the biggest content pod, ties broken by [_priority].
  static Pod primary(Layout layout) {
    final pods = [...layout.pods]
      ..sort((a, b) {
        final media = (b.kind.isMedia ? 1 : 0) - (a.kind.isMedia ? 1 : 0);
        if (media != 0) return media;
        final area = b.area - a.area;
        if (area != 0) return area;
        return _priority.indexOf(a.kind) - _priority.indexOf(b.kind);
      });
    return pods.first;
  }

  /// Tab order on a phone: the primary pod first, the rest by priority.
  static List<Pod> tabs(Layout layout) {
    final first = primary(layout);
    final rest = layout.pods.where((p) => p.id != first.id).toList()
      ..sort((a, b) => _priority.indexOf(a.kind) - _priority.indexOf(b.kind));
    return [first, ...rest];
  }
}
