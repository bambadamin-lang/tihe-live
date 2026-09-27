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
import 'theme/materials.dart';
import 'theme/skeuo.dart';

/// The live classroom (docs/11-live-classroom.md). Give it a [ClassroomSession] — from
/// `openClassroom` in production, or built from fakes in tests and the demo — and it runs the
/// class until the user leaves, the host ends it, or access is lost.
///
/// Persian and right-to-left throughout, in the classroom's own skeuomorphic theme; the host
/// app's theme does not leak in, and this page's theme does not leak out.
class ClassroomPage extends StatefulWidget {
  const ClassroomPage({super.key, required this.session, this.onExit});

  final ClassroomSession session;

  /// Called once the user dismisses the exit screen.
  final void Function(ClassroomExit exit)? onExit;

  @override
  State<ClassroomPage> createState() => _ClassroomPageState();
}

class _ClassroomPageState extends State<ClassroomPage> {
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

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [classroomSessionProvider.overrideWithValue(widget.session)],
    child: Theme(
      data: buildClassroomThemeData(),
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
  );
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
      child: WoodDesk(
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
                              child: BrassPlate(
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

/// Toasts: paper slips pinned under the top bar.
class _Notices extends ConsumerWidget {
  const _Notices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(classroomViewProvider.select((v) => v.notices));
    final session = ref.read(classroomSessionProvider);
    final t = ClassroomTheme.of(context);
    return PositionedDirectional(
      top: 58,
      start: 0,
      end: 0,
      child: Column(
        children: [
          for (final n in notices.reversed.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Dismissible(
                key: ValueKey(n.id),
                onDismissed: (_) => session.dismissNotice(n.id),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: t.paper,
                    borderRadius: BorderRadius.circular(8),
                    border: BorderDirectional(
                      start: BorderSide(
                        width: 5,
                        color: switch (n.tone) {
                          NoticeTone.alert => t.ledRed,
                          NoticeTone.warning => t.ledAmber,
                          NoticeTone.success => t.ledGreen,
                          NoticeTone.info => t.pinNavy,
                        },
                      ),
                    ),
                    boxShadow: t.raised,
                  ),
                  child: Text(
                    n.textFa,
                    style: TextStyle(color: t.ink, fontWeight: FontWeight.w600),
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
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: WoodDesk(
      child: Center(
        child: SizedBox(
          width: 420,
          height: 220,
          child: PaperCard(
            inset: false,
            padding: 24,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(onPressed: onClose, child: const Text('بازگشت')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
