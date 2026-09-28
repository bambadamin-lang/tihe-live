import 'package:flutter/material.dart';

import 'motion.dart';

/// Opens a dialog that rises and sharpens into place over the dimmed class, and leaves quicker
/// than it came. Carries the classroom's theme with it: routes do not inherit it on their own.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
  bool barrierDismissible = true,
}) {
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context).context,
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    transitionDuration: Motion.of(context, Motion.medium),
    pageBuilder: (context, _, _) =>
        themes.wrap(SafeArea(child: Builder(builder: builder))),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.enter,
        reverseCurve: Motion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// A full-screen route into or out of the classroom: the new page fades in while settling from
/// slightly larger, the old one dims back. Used by apps to open [ClassroomPage].
Route<T> classroomRoute<T>(BuildContext context, WidgetBuilder builder) =>
    PageRouteBuilder<T>(
      transitionDuration: Motion.of(context, Motion.slow),
      reverseTransitionDuration: Motion.of(context, Motion.medium),
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Motion.enter,
          reverseCurve: Motion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 1.03, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
