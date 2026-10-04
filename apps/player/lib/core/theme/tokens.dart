import 'package:flutter/widgets.dart';

/// Spacing scale. A 4-point grid: every gap in the app is one of these, so rhythm stays consistent
/// without each screen inventing its own numbers.
abstract final class AppSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;
}

/// Corner radii. Small and consistent: large radii on every container is what makes an interface
/// look like a toy.
abstract final class AppRadius {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double full = 999;

  static const smAll = BorderRadius.all(Radius.circular(sm));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const lgAll = BorderRadius.all(Radius.circular(lg));
}

/// Motion. Short and eased-out: feedback should feel immediate, never decorative.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 260);
  static const curve = Curves.easeOutCubic;
}

/// Window size classes. Layouts switch pattern at these widths (bottom bar → rail → sidebar), rather
/// than scaling one desktop layout down.
enum WindowSize {
  compact,
  medium,
  expanded;

  static const mediumMin = 600.0;
  static const expandedMin = 1024.0;

  static WindowSize of(double width) {
    if (width >= expandedMin) return WindowSize.expanded;
    if (width >= mediumMin) return WindowSize.medium;
    return WindowSize.compact;
  }

  bool get isCompact => this == WindowSize.compact;
  bool get isExpanded => this == WindowSize.expanded;
}

extension WindowSizeContext on BuildContext {
  WindowSize get windowSize => WindowSize.of(MediaQuery.sizeOf(this).width);

  /// Horizontal page gutter for the current size class.
  double get pageGutter => switch (windowSize) {
    WindowSize.compact => AppSpace.x4,
    WindowSize.medium => AppSpace.x6,
    WindowSize.expanded => AppSpace.x10,
  };
}
