import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../data/gateway_client.dart';
import '../../data/media.dart';
import '../../domain/persian.dart';
import '../../state/providers.dart';
import '../classroom_page.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import '../theme/motion.dart';
import '../theme/transitions.dart';
import 'layout_picker.dart';

/// Opens a dialog that still sees the classroom's providers (dialogs live above the page's
/// ProviderScope in the widget tree).
Future<T?> showClassroomDialog<T>(BuildContext context, Widget child) =>
    showGlassDialog<T>(
      context: context,
      barrierColor: ClassroomTheme.of(context).scrim,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    );

/// The class title, the live clock and recording state, who is here, the connection, and the
/// light/dark switch — as glass pills floating over the canvas.
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ClassroomTheme.of(context);
    final title = ref.watch(
      classroomViewProvider.select((v) => v.room?.title ?? v.classTitle),
    );
    final startedAt = ref.watch(
      classroomViewProvider.select((v) => v.room?.startedAt),
    );
    final recording = ref.watch(
      classroomViewProvider.select((v) => v.room?.recording.active ?? false),
    );
    final online = ref.watch(
      classroomViewProvider.select((v) => v.room?.online.length ?? 0),
    );
    final status = ref.watch(classroomViewProvider.select((v) => v.gateway));
    final capturing = ref.watch(
      classroomViewProvider.select((v) => v.capturing.length),
    );
    final appearance = ClassroomAppearance.maybeOf(context);
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final plate = GlassPill(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
    final classLamps = [
      if (startedAt != null) _LiveClock(startedAt: DateTime.parse(startedAt)),
      if (recording)
        Appear(
          key: const ValueKey('recording'),
          offset: const Offset(0, -6),
          scale: 0.9,
          child: GlassPill(
            leading: PulsingDot(color: t.danger),
            child: Text(narrow ? 'ضبط' : 'در حال ضبط'),
          ),
        ),
    ];
    final roomLamps = [
      if (capturing > 0)
        Tooltip(
          key: const ValueKey('capturing'),
          message:
              'شرکت‌کنندگانی که در حال ضبط صفحه‌اند؛ نمای آن‌ها سانسور شده است',
          child: GlassPill(
            fill: t.dangerSubtle,
            leading: Icon(
              ClassroomIcons.captureBlocked,
              size: 14,
              color: t.danger,
            ),
            child: Text(
              '${toPersianDigits(capturing)} ضبط',
              style: TextStyle(color: t.danger),
            ),
          ),
        ),
      Tooltip(
        message: 'حاضران',
        child: GlassPill(
          leading: Icon(
            ClassroomIcons.people,
            size: 14,
            color: t.textSecondary,
          ),
          child: RollingText(toPersianDigits(online)),
        ),
      ),
      _ConnectionLamp(status: status),
      if (appearance != null)
        _ThemeSwitch(
          dark: appearance.brightness == Brightness.dark,
          onPressed: appearance.onToggle,
        ),
    ];
    // Wide: class lamps by the title, room lamps at the far end. Narrow: they wrap.
    final lamps = narrow
        ? Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [...classLamps, ...roomLamps],
          )
        : Row(
            children: [
              for (final lamp in classLamps)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: lamp,
                ),
              const Spacer(),
              for (final lamp in roomLamps)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: lamp,
                ),
            ],
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      // A phone has no room for the title beside the lamps: it gets its own row.
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [plate, const SizedBox(height: 8), lamps],
            )
          : Row(
              children: [
                Flexible(child: plate),
                const SizedBox(width: 8),
                Expanded(child: lamps),
              ],
            ),
    );
  }
}

class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch({required this.dark, required this.onPressed});

  final bool dark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Glass(
    radius: 999,
    shadow: false,
    padding: const EdgeInsets.all(1),
    child: GlassIconButton(
      icon: dark ? ClassroomIcons.light : ClassroomIcons.dark,
      tooltip: dark ? 'پوستهٔ روشن' : 'پوستهٔ تیره',
      size: 30,
      iconSize: 15,
      onPressed: onPressed,
    ),
  );
}

class _LiveClock extends StatefulWidget {
  const _LiveClock({required this.startedAt});
  final DateTime startedAt;

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  /// Ticks as each elapsed second turns over, so the clock changes on time and only then.
  void _scheduleTick() {
    final elapsed = DateTime.now().difference(widget.startedAt);
    final toNext =
        Duration.microsecondsPerSecond -
        elapsed.inMicroseconds % Duration.microsecondsPerSecond;
    _timer = Timer(Duration(microseconds: toNext + 2000), () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Ticks every second: its own layer, so the tick repaints the clock and nothing else.
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: GlassPill(
      leading: StatusDot(color: ClassroomTheme.of(context).success),
      child: Text(
        'زنده  ${elapsedClock(DateTime.now().difference(widget.startedAt))}',
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    ),
  );
}

class _ConnectionLamp extends StatelessWidget {
  const _ConnectionLamp({required this.status});
  final GatewayStatus status;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final (color, label) = switch (status) {
      GatewayStatus.online => (t.success, 'متصل'),
      GatewayStatus.connecting => (t.warning, 'در حال اتصال'),
      GatewayStatus.reconnecting => (t.warning, 'اتصال دوباره…'),
      GatewayStatus.closed => (t.danger, 'قطع'),
    };
    return GlassPill(
      leading: status == GatewayStatus.online
          ? StatusDot(color: color, size: 7)
          : PulsingDot(color: color, size: 7),
      child: Text(label),
    );
  }
}

/// The dock: microphone, camera and screen share, the raised hand, and the host's layout,
/// settings and end-of-class keys, grouped and floating centred over the canvas.
class ControlBar extends ConsumerWidget {
  const ControlBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(classroomSessionProvider);
    final view = ref.watch(classroomViewProvider);
    final t = ClassroomTheme.of(context);
    final local = view.media.local;
    final me = view.me;
    final hands = view.room?.raisedHands ?? const <ParticipantState>[];
    final position = hands.indexWhere((p) => p.userId == view.userId);
    final narrow = MediaQuery.sizeOf(context).width < 640;

    final media = [
      MediaToggle(
        on: local?.micOn ?? false,
        locked: !view.can(Capability.publishAudio),
        icon: ClassroomIcons.mic,
        offIcon: ClassroomIcons.micOff,
        label: 'میکروفون',
        onPressed: session.toggleMicrophone,
      ),
      MediaToggle(
        on: local?.cameraOn ?? false,
        locked: !view.can(Capability.publishVideo),
        icon: ClassroomIcons.camera,
        offIcon: ClassroomIcons.cameraOff,
        label: 'دوربین',
        onPressed: session.toggleCamera,
      ),
      if (!narrow || view.can(Capability.publishScreen))
        // Sharing is a thing you start, not a thing you mute: off is neutral, not red.
        DockButton(
          icon: (local?.screenOn ?? false)
              ? ClassroomIcons.screenShareOff
              : view.can(Capability.publishScreen)
              ? ClassroomIcons.screenShare
              : ClassroomIcons.lock,
          label: 'اشتراک صفحه',
          toggled: local?.screenOn ?? false,
          tint: (local?.screenOn ?? false) ? t.accent : null,
          tooltip: view.can(Capability.publishScreen)
              ? 'اشتراک صفحه'
              : 'اشتراک صفحه — نیاز به اجازهٔ میزبان',
          disabledCursor: SystemMouseCursors.forbidden,
          onPressed:
              !(local?.screenOn ?? false) && !view.can(Capability.publishScreen)
              ? null
              : () => (local?.screenOn ?? false)
                    ? session.stopScreenShare()
                    : _pickScreen(context, ref),
        ),
      if (me == null || me.role.rank < ClassRole.cohost.rank)
        HandToggle(
          raised: me?.hand != null,
          queuePosition: position >= 0 ? position + 1 : null,
          onPressed: (me?.hand != null || view.can(Capability.handRaise))
              ? session.toggleHand
              : null,
        ),
    ];

    final host = [
      if (view.can(Capability.layoutChange))
        DockButton(
          icon: ClassroomIcons.layout,
          label: 'چیدمان',
          showLabel: !narrow,
          onPressed: () =>
              showClassroomDialog<void>(context, const LayoutPickerSheet()),
        ),
      if (view.can(Capability.participantsManage))
        DockButton(
          icon: ClassroomIcons.settings,
          label: 'تنظیمات کلاس',
          showLabel: !narrow,
          onPressed: () =>
              showClassroomDialog<void>(context, const ClassSettingsSheet()),
        ),
    ];

    final exits = [
      if (view.can(Capability.classEnd))
        DockButton(
          icon: ClassroomIcons.endClass,
          label: 'پایان کلاس',
          tint: t.danger,
          solid: true,
          showLabel: !narrow,
          onPressed: () => _confirmEnd(context, ref),
        ),
      DockButton(
        icon: ClassroomIcons.leave,
        label: 'خروج',
        showLabel: !narrow,
        onPressed: session.leave,
      ),
    ];

    Widget group(List<Widget> items) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final w in items)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: w),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Center(
        child: GlassBar(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: narrow
              ? Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [...media, ...host, ...exits],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    group(media),
                    if (host.isNotEmpty) ...[
                      const BarDivider(height: 42),
                      group(host),
                    ],
                    const BarDivider(height: 42),
                    group(exits),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _pickScreen(BuildContext context, WidgetRef ref) async {
    final session = ref.read(classroomSessionProvider);
    final sources = await session.screenSources();
    if (sources.isEmpty) {
      // Mobile: the OS shows its own picker.
      await session.startScreenShare();
      return;
    }
    if (!context.mounted) return;
    final chosen = await showClassroomDialog<ScreenSource>(
      context,
      ScreenPickerSheet(sources: sources),
    );
    if (chosen != null) await session.startScreenShare(chosen);
  }

  Future<void> _confirmEnd(BuildContext context, WidgetRef ref) async {
    final danger = ClassroomTheme.of(context).danger;
    final sure = await showClassroomDialog<bool>(
      context,
      Builder(
        builder: (context) => GlassSheet(
          title: 'پایان کلاس',
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'کلاس برای همه تمام می‌شود و ضبط آن به کتابخانه می‌رود.',
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: danger),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('پایان کلاس برای همه'),
              ),
            ],
          ),
        ),
      ),
    );
    if (sure ?? false) await ref.read(classroomSessionProvider).endClass();
  }
}

/// Screens and windows to share, desktop only. The classroom's own window is not offered —
/// sharing it would show the class inside itself (docs/11 §7).
class ScreenPickerSheet extends StatelessWidget {
  const ScreenPickerSheet({super.key, required this.sources});

  final List<ScreenSource> sources;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final offered =
        sources.where((s) => !s.name.toLowerCase().contains('tihe')).toList()
          // Windows first: sharing one window is the safer default (and required on macOS 15+).
          ..sort((a, b) => (a.isScreen ? 1 : 0) - (b.isScreen ? 1 : 0));
    return GlassSheet(
      title: 'اشتراک صفحه',
      width: 640,
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.25,
        children: [
          for (final s in offered)
            GlassPressable(
              onTap: () => Navigator.of(context).pop(s),
              semanticLabel: s.name,
              builder: (context, state) => Column(
                children: [
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: t.screen,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: state.hovered ? t.accent : t.edgeLow,
                          width: state.hovered ? 1.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: s.thumbnail != null
                          ? Image.memory(
                              s.thumbnail!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            )
                          : Icon(
                              s.isScreen
                                  ? ClassroomIcons.screen
                                  : ClassroomIcons.window,
                              color: Colors.white38,
                              size: 32,
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.isScreen ? 'کل صفحه — ${s.name}' : s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The host's room policy (docs/11 §3) and whole-class actions.
class ClassSettingsSheet extends ConsumerWidget {
  const ClassSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(
      classroomViewProvider.select((v) => v.room?.policy),
    );
    final session = ref.read(classroomSessionProvider);
    if (policy == null) return const SizedBox.shrink();
    final values = policy.toJson();
    return GlassSheet(
      title: 'تنظیمات کلاس',
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'آنچه شرکت‌کنندگان بدون اجازهٔ جداگانه می‌توانند:',
                style: TextStyle(fontSize: 13),
              ),
            ),
            for (final entry in policyLabelsFa.entries)
              SwitchListTile(
                dense: true,
                title: Text(entry.value),
                value: values[entry.key] as bool,
                onChanged: (on) => session.send(UpdatePolicy({entry.key: on})),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => session.send(const MuteAll()),
                  icon: const Icon(ClassroomIcons.muteAll, size: 16),
                  label: const Text('بی‌صدا کردن همه'),
                ),
                OutlinedButton.icon(
                  onPressed: () => session.send(const LowerAllHands()),
                  icon: const Icon(ClassroomIcons.lowerAll, size: 16),
                  label: const Text('پایین آوردن همهٔ دست‌ها'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
