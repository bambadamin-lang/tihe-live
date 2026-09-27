import 'package:flutter/material.dart';

import '../../domain/persian.dart';

import 'classroom_theme.dart';
import 'materials.dart';

/// The classroom's physical controls. Each looks like an object on a teacher's desk and
/// behaves like one: it presses in, lights up, and shows when it cannot be used.

/// A pod: a paper card with an inset screen and a paper tab for its name.
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.inset = true,
    this.padding = 9,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;

  /// Show the content as an inset, dark "screen" (video) rather than on the paper itself.
  final bool inset;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: t.raised,
      ),
      child: CustomPaint(
        painter: PaperPainter(t),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 4,
                    end: 2,
                    bottom: 7,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [t.brassHigh, t.brassDark],
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: t.inkSoft,
                            shadows: const [
                              Shadow(color: Colors.white, offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              Expanded(
                child: inset
                    ? DecoratedBox(
                        // Foreground: only the rim is drawn over the content, never a fill.
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        position: DecorationPosition.foreground,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ColoredBox(color: t.screenGlass, child: child),
                        ),
                      )
                    : child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A brushed-aluminium bar, for the control bar and tool trays.
class MetalBar extends StatelessWidget {
  const MetalBar({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: t.raised,
      ),
      child: CustomPaint(
        painter: BrushedMetalPainter(t, radius: radius),
        child: Padding(
          padding:
              padding ??
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

/// A small glowing lamp.
class Led extends StatelessWidget {
  const Led({super.key, required this.color, this.on = true, this.size = 10});

  final Color color;
  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: const Alignment(-0.35, -0.35),
        colors: on
            ? [
                Color.lerp(color, Colors.white, 0.65)!,
                color,
                Color.lerp(color, Colors.black, 0.35)!,
              ]
            : [
                const Color(0xFF6D6A66),
                const Color(0xFF3C3A38),
                const Color(0xFF252422),
              ],
        stops: const [0, 0.45, 1],
      ),
      border: Border.all(
        color: Colors.black.withValues(alpha: 0.5),
        width: 0.8,
      ),
      boxShadow: on
          ? [
              BoxShadow(
                color: color.withValues(alpha: 0.75),
                blurRadius: size * 1.2,
              ),
            ]
          : null,
    ),
  );
}

/// A LED that breathes — for "recording".
class PulsingLed extends StatefulWidget {
  const PulsingLed({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  State<PulsingLed> createState() => _PulsingLedState();
}

class _PulsingLedState extends State<PulsingLed>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.45, end: 1.0).animate(_controller),
    child: Led(color: widget.color, size: widget.size),
  );
}

/// An engraved brass plaque, for the class title and status.
class BrassPlate extends StatelessWidget {
  const BrassPlate({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: t.brassPlate,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.brassDark, width: 1),
        boxShadow: t.lifted,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: const Color(0xFF3A2A10),
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(
              color: t.brassHigh.withValues(alpha: 0.9),
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// A rocker switch for mic, camera and screen share: the pressed half sits lower, a lamp shows
/// the state, and a locked switch shows a padlock instead of pretending to work.
class RockerSwitch extends StatelessWidget {
  const RockerSwitch({
    super.key,
    required this.on,
    required this.icon,
    required this.offIcon,
    required this.label,
    this.onPressed,
    this.locked = false,
  });

  final bool on;
  final IconData icon;
  final IconData offIcon;
  final String label;
  final VoidCallback? onPressed;

  /// The class does not allow this right now (no capability).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final enabled = onPressed != null && !(locked && !on);
    return Tooltip(
      message: locked && !on ? '$label — نیاز به اجازهٔ میزبان' : label,
      child: Semantics(
        button: true,
        toggled: on,
        enabled: enabled,
        label: label,
        child: GestureDetector(
          onTap: enabled ? onPressed : null,
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.forbidden,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 44,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2926),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      const BoxShadow(
                        color: Colors.white70,
                        offset: Offset(0, 1),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        // The pressed half is darker: which half is down is the state.
                        colors: on
                            ? [
                                const Color(0xFF55524D),
                                const Color(0xFF3E3B37),
                                const Color(0xFF6B6760),
                              ]
                            : [
                                const Color(0xFF7A766F),
                                const Color(0xFF4A4742),
                                const Color(0xFF35322E),
                              ],
                        stops: const [0, 0.5, 1],
                      ),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          locked && !on
                              ? Icons.lock_outline
                              : (on ? icon : offIcon),
                          size: 20,
                          color: enabled
                              ? const Color(0xFFEDE7DA)
                              : const Color(0xFF8E8A82),
                        ),
                        PositionedDirectional(
                          top: 3,
                          end: 4,
                          child: Led(
                            color: on ? t.ledGreen : t.ledRed,
                            on: on || !locked,
                            size: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: t.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round domed push-button that sinks when pressed.
class DomeButton extends StatefulWidget {
  const DomeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.size = 44,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final bool showLabel;

  @override
  State<DomeButton> createState() => _DomeButtonState();
}

class _DomeButtonState extends State<DomeButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final base = widget.color ?? t.metalMid;
    final enabled = widget.onPressed != null;
    final dome = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: _down
              ? const Alignment(0, 0.3)
              : const Alignment(-0.3, -0.45),
          radius: 0.95,
          colors: [
            Color.lerp(base, Colors.white, _down ? 0.15 : 0.55)!,
            base,
            Color.lerp(base, Colors.black, 0.45)!,
          ],
          stops: const [0, 0.55, 1],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.45)),
        boxShadow: _down ? null : t.lifted,
      ),
      child: Icon(
        widget.icon,
        size: widget.size * 0.46,
        color: enabled ? Colors.white : Colors.white54,
        shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
      ),
    );
    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        label: widget.label,
        enabled: enabled,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled
              ? (_) {
                  setState(() => _down = false);
                  widget.onPressed!();
                }
              : null,
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSlide(
                  duration: const Duration(milliseconds: 80),
                  offset: Offset(0, _down ? 0.04 : 0),
                  child: dome,
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: t.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The raise-hand paddle: a wooden paddle that swings up when the hand is raised.
class HandPaddle extends StatelessWidget {
  const HandPaddle({
    super.key,
    required this.raised,
    required this.onPressed,
    this.queuePosition,
  });

  final bool raised;
  final VoidCallback? onPressed;

  /// 1-based place in the hand queue, shown while raised.
  final int? queuePosition;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final label = raised ? 'پایین آوردن دست' : 'بالا بردن دست';
    return Tooltip(
      message: onPressed == null ? 'میزبان بالا بردن دست را بسته است' : label,
      child: Semantics(
        button: true,
        toggled: raised,
        label: label,
        child: GestureDetector(
          onTap: onPressed,
          child: MouseRegion(
            cursor: onPressed != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.forbidden,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 50,
                  height: 44,
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    turns: raised ? 0 : -0.1,
                    alignment: Alignment.bottomCenter,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        // The handle.
                        Positioned(
                          bottom: 0,
                          child: Container(
                            width: 8,
                            height: 20,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              gradient: LinearGradient(
                                colors: [t.woodLight, t.woodDark],
                              ),
                              boxShadow: t.lifted,
                            ),
                          ),
                        ),
                        // The paddle, with the hand painted on it.
                        Container(
                          width: 34,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.3, -0.4),
                              colors: raised
                                  ? [
                                      const Color(0xFFFFE08A),
                                      t.ledAmber,
                                      const Color(0xFFB77A00),
                                    ]
                                  : [t.woodLight, t.woodMid, t.woodDark],
                            ),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.4),
                            ),
                            boxShadow: t.lifted,
                          ),
                          child: Icon(
                            Icons.back_hand,
                            size: 17,
                            color: raised
                                ? const Color(0xFF5A3A00)
                                : const Color(0xFFE8D6BC),
                          ),
                        ),
                        if (raised && queuePosition != null)
                          PositionedDirectional(
                            top: 0,
                            end: 0,
                            child: _Badge(
                              text: toPersianDigits(queuePosition!),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  raised ? 'دست بالاست' : 'دست',
                  style: TextStyle(
                    fontSize: 11,
                    color: t.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0xFFB3261E),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white, width: 1.2),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// An enamel lapel pin — the role badge.
class EnamelPin extends StatelessWidget {
  const EnamelPin({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.3)!, color],
        ),
        border: Border.all(color: t.brass, width: 1.4),
        boxShadow: t.lifted,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A paper dialog sheet for menus and pickers.
class PaperSheet extends StatelessWidget {
  const PaperSheet({
    super.key,
    required this.title,
    required this.child,
    this.width = 460,
  });

  final String title;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: t.raised,
          ),
          child: CustomPaint(
            painter: PaperPainter(t),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'بستن',
                        icon: Icon(Icons.close, color: t.inkSoft),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
