import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts.dart';
import '../state/classroom_session.dart';
import '../state/providers.dart';
import 'controls/bars.dart';
import 'pods/chat_pod.dart';
import 'pods/participants_pod.dart';
import 'protection/censor_screen.dart';
import 'protection/watermark_overlay.dart';
import 'stage/stage_focus.dart';
import 'stage/stage_view.dart';
import 'theme/classroom_theme.dart';
import 'theme/cursor.dart';
import 'theme/fonts.dart';
import 'theme/glass.dart';
import 'theme/motion.dart';

/// The live classroom (docs/11-live-classroom.md). Give it a [ClassroomSession] — from
/// `openClassroom` in production, or built from fakes in tests and the demo — and it runs the
/// class until the user leaves, the host ends it, or access is lost.
///
/// Persian and right-to-left throughout, in the classroom's own glass theme. It follows the host
/// app's light or dark mode unless given [brightness], and the student can switch it from the
/// top bar for the rest of the class. The host app's theme does not otherwise leak in, and this
/// page's theme does not leak out.
class ClassroomPage extends StatefulWidget {
  const ClassroomPage({
    super.key,
    required this.session,
    this.onExit,
    this.brightness,
    this.onBrightnessChanged,
  });

  final ClassroomSession session;

  /// Called once the user dismisses the exit screen.
  final void Function(ClassroomExit exit)? onExit;

  /// Light or dark. Null follows the host app's theme.
  final Brightness? brightness;

  /// Called when the student switches the theme in class, so the host app can remember it.
  final ValueChanged<Brightness>? onBrightnessChanged;

  @override
  State<ClassroomPage> createState() => _ClassroomPageState();
}

class _ClassroomPageState extends State<ClassroomPage> {
  Brightness? _chosen;
  final _focus = StageFocus();

  @override
  void initState() {
    super.initState();
    PeydaFonts.ensureLoaded();
    widget.session.open();
  }

  @override
  void dispose() {
    _focus.dispose();
    widget.session.dispose();
    super.dispose();
  }

  void _toggle(Brightness current) {
    final next = current == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    setState(() => _chosen = next);
    widget.onBrightnessChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final brightness =
        _chosen ?? widget.brightness ?? Theme.of(context).brightness;
    return ProviderScope(
      overrides: [classroomSessionProvider.overrideWithValue(widget.session)],
      child: Theme(
        data: buildClassroomThemeData(ClassroomTheme.forBrightness(brightness)),
        child: ClassroomAppearance(
          brightness: brightness,
          onToggle: () => _toggle(brightness),
          child: Localizations.override(
            context: context,
            locale: const Locale('fa'),
            delegates: GlobalMaterialLocalizations.delegates,
            child: Directionality(
              textDirection: TextDirection.rtl,
              // The brand cursor across the class; an app-wide GlowCursorScope also draws it
              // where the platform cannot (see cursor.dart).
              child: MouseRegion(
                cursor: GlowCursors.basic,
                child: StageFocusScope(
                  focus: _focus,
                  child: _Classroom(onExit: widget.onExit),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page's light/dark state, for the switch in the top bar.
class ClassroomAppearance extends InheritedWidget {
  const ClassroomAppearance({
    super.key,
    required this.brightness,
    required this.onToggle,
    required super.child,
  });

  final Brightness brightness;
  final VoidCallback onToggle;

  static ClassroomAppearance? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ClassroomAppearance>();

  @override
  bool updateShouldNotify(ClassroomAppearance old) =>
      old.brightness != brightness;
}

class _Classroom extends ConsumerWidget {
  const _Classroom({required this.onExit});

  final void Function(ClassroomExit exit)? onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exit = ref.watch(classroomViewProvider.select((v) => v.exit));
    final censored = ref.watch(
      classroomViewProvider.select((v) => v.capture.censor),
    );
    final ready = ref.watch(
      classroomViewProvider.select((v) => v.room != null),
    );

    if (exit != null) {
      return _ExitScreen(
        message: ref.read(classroomViewProvider).exitMessageFa ?? '',
        onClose: () => onExit?.call(exit),
      );
    }
    if (censored) {
      return Material(
        type: MaterialType.transparency,
        child: CensorScreen(
          verdict: ref.watch(classroomViewProvider.select((v) => v.capture)),
        ),
      );
    }

    final watermark = ref.watch(
      classroomViewProvider.select((v) => v.watermark),
    );
    return Material(
      type: MaterialType.transparency,
      child: GlassBackdrop(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  const TopBar(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: ready
                          ? Stack(
                              children: [
                                const Positioned.fill(child: StageView()),
                                const Positioned.fill(child: _SidePanel()),
                                const Positioned.fill(
                                  child: IgnorePointer(child: ReactionFloat()),
                                ),
                                // Over every pod and panel, under nothing: see docs/11 §9.
                                Positioned.fill(
                                  child: WatermarkOverlay(spec: watermark),
                                ),
                              ],
                            )
                          : const Center(
                              child: GlassPill(
                                leading: SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.75,
                                  ),
                                ),
                                child: Text('در حال ورود به کلاس…'),
                              ),
                            ),
                    ),
                  ),
                  const ControlBar(),
                ],
              ),
              const _Notices(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toasts: glass slips under the top bar, with a dot for their tone.
class _Notices extends ConsumerWidget {
  const _Notices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(classroomViewProvider.select((v) => v.notices));
    final session = ref.read(classroomSessionProvider);
    final t = ClassroomTheme.of(context);
    return PositionedDirectional(
      top: 66,
      start: 0,
      end: 0,
      child: Column(
        children: [
          for (final n in notices.reversed.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Dismissible(
                key: ValueKey(n.id),
                onDismissed: (_) => session.dismissNotice(n.id),
                child: Appear(
                  offset: const Offset(0, -14),
                  scale: 0.94,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Glass(
                      radius: 14,
                      strong: true,
                      overlay: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusDot(
                            color: switch (n.tone) {
                              NoticeTone.alert => t.danger,
                              NoticeTone.warning => t.warning,
                              NoticeTone.success => t.success,
                              NoticeTone.info => t.accent,
                            },
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              n.textFa,
                              style: TextStyle(
                                color: t.text,
                                fontWeight: FontWeight.w500,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExitScreen extends StatelessWidget {
  const _ExitScreen({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: GlassBackdrop(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Appear(
                duration: Motion.slow,
                offset: const Offset(0, 18),
                scale: 0.95,
                child: Glass(
                  radius: 24,
                  padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: IconTile(
                          icon: ClassroomIcons.classEnded,
                          size: 56,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.6,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(height: 22),
                      GlowButton(
                        label: 'بازگشت',
                        height: 46,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chat or people, when the host's layout has no pod for them: a glass panel over the stage's
/// start edge, opened and closed from the dock.
class _SidePanel extends StatelessWidget {
  const _SidePanel();

  @override
  Widget build(BuildContext context) {
    final focus = StageFocusScope.maybeOf(context);
    final kind = focus?.drawer;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth < 600 ? box.maxWidth : 380.0;
        return Stack(
          children: [
            PositionedDirectional(
              top: 6,
              bottom: 6,
              start: 6,
              width: width - 12,
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.medium),
                switchInCurve: Motion.enter,
                switchOutCurve: Motion.exit,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: Offset(
                        Directionality.of(context) == TextDirection.rtl
                            ? 0.08
                            : -0.08,
                        0,
                      ),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: kind == null
                    ? const SizedBox.shrink(key: ValueKey('none'))
                    : KeyedSubtree(
                        key: ValueKey(kind),
                        child: Glass(
                          strong: true,
                          overlay: true,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 34,
                                child: Row(
                                  children: [
                                    Icon(
                                      kind == PodKind.chat
                                          ? ClassroomIcons.chat
                                          : ClassroomIcons.people,
                                      size: 18,
                                      color: ClassroomTheme.of(
                                        context,
                                      ).textSecondary,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        kind.labelFa,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: ClassroomTheme.of(
                                            context,
                                          ).text,
                                        ),
                                      ),
                                    ),
                                    GlassIconButton(
                                      icon: ClassroomIcons.close,
                                      tooltip: 'بستن',
                                      onPressed: focus!.closeDrawer,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: kind == PodKind.chat
                                    ? const ChatPod()
                                    : const ParticipantsPod(),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Reactions floating up over the stage: each one-emoji chat message that arrives while the
/// class runs rises from the dock and fades, drifting a little as it goes.
class ReactionFloat extends ConsumerStatefulWidget {
  const ReactionFloat({super.key});

  @override
  ConsumerState<ReactionFloat> createState() => _ReactionFloatState();
}

typedef _Floater = ({String id, String emoji, double lane, Duration born});

class _ReactionFloatState extends ConsumerState<ReactionFloat>
    with SingleTickerProviderStateMixin {
  static const _life = Duration(milliseconds: 2600);
  late final _ticker = createTicker(_tick);
  final _floaters = <_Floater>[];
  Set<String>? _seen;

  /// Frame time since the ticker started; it restarts only once every floater is gone.
  Duration _now = Duration.zero;

  void _tick(Duration elapsed) {
    setState(() {
      _now = elapsed;
      _floaters.removeWhere((f) => _now - f.born > _life);
    });
    if (_floaters.isEmpty) {
      _ticker.stop();
      _now = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(
      classroomViewProvider.select(
        (v) => v.room?.chat ?? const <ChatMessage>[],
      ),
    );
    // History does not float: only what arrives after the page opened.
    final seen = _seen ??= {for (final m in chat) m.id};
    for (final m in chat) {
      if (!seen.add(m.id) || !isReaction(m.text)) continue;
      if (Motion.reduced(context)) continue;
      _floaters.add((
        id: m.id,
        emoji: m.text.trim(),
        lane: ((m.id.hashCode % 1000) / 1000 - 0.5) * 0.5,
        born: _now,
      ));
      if (!_ticker.isActive) _ticker.start();
    }
    if (_floaters.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          for (final f in _floaters)
            Builder(
              builder: (context) {
                final v =
                    ((_now - f.born).inMilliseconds / _life.inMilliseconds)
                        .clamp(0.0, 1.0);
                final rise = Curves.easeOutCubic.transform(v);
                final x =
                    box.maxWidth * (0.5 + f.lane) +
                    18 * math.sin(v * math.pi * 2.5);
                final y = box.maxHeight * (1 - 0.7 * rise);
                final opacity = v < 0.15
                    ? v / 0.15
                    : 1 - ((v - 0.6) / 0.4).clamp(0, 1);
                return Positioned(
                  left: x - 24,
                  top: y - 24,
                  child: Opacity(
                    opacity: opacity.toDouble(),
                    child: Transform.scale(
                      scale:
                          0.7 +
                          0.5 *
                              Curves.easeOutBack.transform(
                                (v * 4).clamp(0.0, 1.0),
                              ),
                      child: Text(
                        f.emoji,
                        style: const TextStyle(fontSize: 38, height: 1.2),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
