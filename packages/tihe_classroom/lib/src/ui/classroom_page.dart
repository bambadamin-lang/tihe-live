import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/classroom_session.dart';
import '../state/providers.dart';
import 'controls/bars.dart';
import 'protection/censor_screen.dart';
import 'protection/watermark_overlay.dart';
import 'stage/stage_view.dart';
import 'theme/classroom_theme.dart';
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

  @override
  void initState() {
    super.initState();
    PeydaFonts.ensureLoaded();
    widget.session.open();
  }

  @override
  void dispose() {
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
              child: _Classroom(onExit: widget.onExit),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ready
                          ? Stack(
                              children: [
                                const Positioned.fill(child: StageView()),
                                // Over every pod, under nothing: see docs/11 §9.
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
      top: 62,
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
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: t.accentSubtle,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            ClassroomIcons.classEnded,
                            size: 22,
                            color: t.accentText,
                          ),
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
                      FilledButton(
                        onPressed: onClose,
                        child: const Text('بازگشت'),
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
