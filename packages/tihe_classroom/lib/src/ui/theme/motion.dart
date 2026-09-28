import 'dart:async';

import 'package:flutter/widgets.dart';

/// Motion for the classroom: short and eased, so the class feels quick rather than busy, and
/// off entirely when the operating system asks for reduced motion.
///
/// Things move only when something happened — a pod joins the stage, a message arrives, a hand
/// goes up. Nothing loops except the live and recording lamps.
abstract final class Motion {
  /// Presses, hovers, small state flips.
  static const fast = Duration(milliseconds: 140);

  /// Things arriving: toasts, messages, queue rows, dialogs.
  static const medium = Duration(milliseconds: 260);

  /// Things moving across the stage: layouts, maximise.
  static const slow = Duration(milliseconds: 380);

  /// Arrivals start quick and settle gently.
  static const enter = Cubic(0.05, 0.7, 0.1, 1);

  /// Departures leave without lingering.
  static const exit = Cubic(0.3, 0, 0.8, 0.15);

  /// Moves between two places on screen.
  static const move = Curves.easeInOutCubicEmphasized;

  /// The operating system's "reduce motion" / "remove animations" setting.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or nothing when motion is reduced.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Fades and slides its child in once, when it first appears. Used for anything that arrives
/// while the class is running; content that was already there when the page opened passes
/// `animate: false` so the history does not replay.
class Appear extends StatefulWidget {
  const Appear({
    super.key,
    required this.child,
    this.animate = true,
    this.delay = Duration.zero,
    this.duration = Motion.medium,
    this.offset = const Offset(0, 10),
    this.scale = 1,
  });

  final Widget child;
  final bool animate;
  final Duration delay;
  final Duration duration;

  /// Where the child starts, in logical pixels, relative to where it ends.
  final Offset offset;

  /// The starting scale; 1 for none.
  final double scale;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.enter,
  );
  Timer? _delay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || Motion.reduced(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delay = Timer(widget.delay, _controller.forward);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Once settled, the child is returned as is: no opacity or transform layers left behind
    // to cost anything on later frames.
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final v = _curve.value;
        if (v >= 1) return child!;
        final dx = widget.offset.dx * (1 - v);
        final dy = widget.offset.dy * (1 - v);
        final s = widget.scale + (1 - widget.scale) * v;
        return Opacity(
          opacity: _controller.value.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(dx, dy, 0)
              ..multiply(Matrix4.diagonal3Values(s, s, 1)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Remembers which items were already shown, so a list can animate only new arrivals — even
/// when a lazily built list rebuilds rows as they scroll back into view.
class SeenSet {
  SeenSet(Iterable<String> initial) : _seen = {...initial};

  final Set<String> _seen;

  /// True the first time [id] is asked about after the list opened.
  bool isNew(String id) => _seen.add(id);
}

/// Text that rolls to its new value — counts and numbers that change while the class runs.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) {
        // The arriving value comes up from below; the old one leaves the same way.
        final incoming = child.key == ValueKey(text);
        final offset = Tween(
          begin: Offset(0, incoming ? 0.6 : -0.6),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: Text(text, key: ValueKey(text), style: style),
    ),
  );
}
