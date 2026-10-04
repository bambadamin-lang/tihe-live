import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../data/media.dart';
import '../../domain/persian.dart';
import '../../state/classroom_session.dart';
import '../../state/providers.dart';
import '../classroom_page.dart';
import '../pods/chat_pod.dart' show reactionEmoji, showEmojiPopover;
import '../stage/stage_focus.dart';
import '../theme/brand.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import '../theme/menu.dart';
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

/// The class on one side — its title, live and recording lamps and clock — and the app on the
/// other: the light/dark switch, the connection and the brand. On a desktop that draws its own
/// window frame, the window buttons sit at the far edge and the bar drags the window.
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
    final status = ref.watch(classroomViewProvider.select((v) => v.gateway));
    final capturing = ref.watch(
      classroomViewProvider.select((v) => v.capturing.length),
    );
    final appearance = ClassroomAppearance.maybeOf(context);
    final chrome = WindowChrome.maybeOf(context);
    final narrow = MediaQuery.sizeOf(context).width < 760;

    final plate = GlassPill(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      leading: Icon(ClassroomIcons.course, size: 17, color: t.textSecondary),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
    );
    final lamps = [
      if (startedAt != null) ...[
        GlassPill(
          leading: StatusDot(color: t.success),
          trailing: Icon(ClassroomIcons.signal, size: 16, color: t.success),
          child: const Text('زنده'),
        ),
        _LiveClock(startedAt: DateTime.parse(startedAt)),
      ],
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
      if (capturing > 0)
        Tooltip(
          key: const ValueKey('capturing'),
          message:
              'شرکت‌کنندگانی که در حال ضبط صفحه‌اند؛ نمای آن‌ها سانسور شده است',
          child: GlassPill(
            fill: t.dangerSubtle,
            leading: Icon(
              ClassroomIcons.captureBlocked,
              size: 15,
              color: t.danger,
            ),
            child: Text(
              '${toPersianDigits(capturing)} ضبط',
              style: TextStyle(color: t.danger),
            ),
          ),
        ),
    ];
    final themeSwitch = appearance == null
        ? null
        : _ThemeSwitch(
            dark: appearance.brightness == Brightness.dark,
            onPressed: appearance.onToggle,
          );

    final Widget bar;
    if (narrow) {
      // A phone has no room for the title beside the lamps: they get their own row.
      bar = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (chrome != null) ...[
                chrome.controls,
                const SizedBox(width: 8),
              ],
              Expanded(child: plate),
              if (themeSwitch != null) ...[
                const SizedBox(width: 8),
                themeSwitch,
              ],
              const SizedBox(width: 10),
              const BrandLockup(compact: true),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...lamps,
              ConnectionPill(status: status),
            ],
          ),
        ],
      );
    } else {
      bar = Row(
        children: [
          if (chrome != null) ...[chrome.controls, const SizedBox(width: 10)],
          Expanded(
            child: Row(
              children: [
                Flexible(child: plate),
                for (final lamp in lamps) ...[const SizedBox(width: 8), lamp],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (themeSwitch != null) ...[themeSwitch, const SizedBox(width: 8)],
          ConnectionPill(status: status),
          const BarDivider(height: 26),
          const BrandLockup(),
        ],
      );
    }
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: bar,
    );
    return chrome == null ? padded : chrome.dragArea(padded);
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
    padding: const EdgeInsets.all(2),
    child: GlassIconButton(
      icon: dark ? ClassroomIcons.light : ClassroomIcons.dark,
      tooltip: dark ? 'پوستهٔ روشن' : 'پوستهٔ تیره',
      size: 34,
      iconSize: 17,
      radius: 999,
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
    // clock, not DateTime: the timer and the time must come from the same clock, or a test's
    // fake timers meet the real second turning over and tick in a burst.
    final elapsed = clock.now().difference(widget.startedAt);
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
    child: Tooltip(
      message: 'مدت کلاس',
      child: GlassPill(
        child: Text(
          elapsedClock(clock.now().difference(widget.startedAt)),
          style: const TextStyle(
            fontSize: 14.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}

typedef _DockState = ({
  bool micOn,
  bool cameraOn,
  bool screenOn,
  bool canAudio,
  bool canVideo,
  bool canScreen,
  bool canRaise,
  bool canChat,
  bool canEnd,
  bool showHand,
  bool handUp,
  int? queue,
  Layout? layout,
});

/// The dock: leaving, the camera and microphone with their device pickers, then the class's
/// tools — more, reactions, screen share, the hand (or, for the host, ending the class), and
/// the chat and people panels — floating centred over the stage.
class ControlBar extends ConsumerWidget {
  const ControlBar({super.key});

  /// Everything the dock shows, as one value: it rebuilds when one of these changes, not on
  /// every board stroke, chat message or speaker change in the class.
  static _DockState _select(ClassroomView v) {
    final local = v.media.local;
    final me = v.me;
    final hand = me?.hand;
    return (
      micOn: local?.micOn ?? false,
      cameraOn: local?.cameraOn ?? false,
      screenOn: local?.screenOn ?? false,
      canAudio: v.can(Capability.publishAudio),
      canVideo: v.can(Capability.publishVideo),
      canScreen: v.can(Capability.publishScreen),
      canRaise: v.can(Capability.handRaise),
      canChat: v.can(Capability.chatSend),
      canEnd: v.can(Capability.classEnd),
      // Cohosts and hosts take the floor; they have no hand to raise.
      showHand: me == null || me.role.rank < ClassRole.cohost.rank,
      handUp: hand != null,
      // 1-based place in the queue: hands are served in the order the server received them.
      queue: hand == null
          ? null
          : 1 +
                (v.room?.participants.values
                        .where(
                          (p) =>
                              p.hand != null &&
                              p.hand!.raisedSeq < hand.raisedSeq,
                        )
                        .length ??
                    0),
      // For the chat and people keys; a layout is replaced, not changed, so this compares by
      // identity.
      layout: v.room?.layout,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(classroomSessionProvider);
    final s = ref.watch(classroomViewProvider.select(_select));
    final focus = StageFocusScope.maybeOf(context);
    final t = ClassroomTheme.of(context);
    final layout = s.layout;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final sharing = s.screenOn;
    final canShare = s.canScreen;
    final canChat = s.canChat;

    Widget media(MediaDeviceKind kind) {
      final mic = kind == MediaDeviceKind.microphone;
      final toggle = MediaToggle(
        on: mic ? s.micOn : s.cameraOn,
        locked: !(mic ? s.canAudio : s.canVideo),
        icon: mic ? ClassroomIcons.mic : ClassroomIcons.camera,
        offIcon: mic ? ClassroomIcons.micOff : ClassroomIcons.cameraOff,
        label: mic ? 'میکروفون' : 'دوربین',
        showLabel: !narrow,
        onPressed: mic ? session.toggleMicrophone : session.toggleCamera,
      );
      if (narrow) return toggle;
      return Builder(
        builder: (context) => SplitDockButton(
          main: toggle,
          moreTooltip: mic ? 'انتخاب میکروفون' : 'انتخاب دوربین',
          onMore: () => _pickDevice(context, ref, kind),
        ),
      );
    }

    Widget panel(PodKind kind, IconData icon, String label) => DockButton(
      icon: icon,
      label: label,
      showLabel: !narrow,
      toggled: focus?.isFocused(kind, layout) ?? false,
      tint: (focus?.isFocused(kind, layout) ?? false) ? t.accentText : null,
      onPressed: focus == null ? null : () => focus.toggle(kind, layout),
    );

    final tools = [
      Builder(
        builder: (context) => DockButton(
          icon: ClassroomIcons.moreHorizontal,
          label: 'بیشتر',
          showLabel: !narrow,
          onPressed: () => _more(context, ref, withPanels: narrow),
        ),
      ),
      Builder(
        builder: (context) => DockButton(
          icon: ClassroomIcons.reactions,
          label: 'واکنش‌ها',
          showLabel: !narrow,
          tooltip: canChat ? 'واکنش‌ها' : 'واکنش‌ها — گفتگو بسته است',
          disabledCursor: SystemMouseCursors.forbidden,
          onPressed: canChat
              ? () async {
                  final emoji = await showEmojiPopover(context, reactionEmoji);
                  if (emoji != null) await session.send(SendChat(emoji));
                }
              : null,
        ),
      ),
      if (!narrow || canShare)
        // Sharing is a thing you start, not a thing you mute: off is neutral, not red.
        DockButton(
          icon: sharing
              ? ClassroomIcons.screenShareOff
              : canShare
              ? ClassroomIcons.screenShare
              : ClassroomIcons.lock,
          label: sharing ? 'توقف اشتراک' : 'اشتراک صفحه',
          showLabel: !narrow,
          toggled: sharing,
          tint: sharing ? t.accentText : null,
          tooltip: canShare
              ? 'اشتراک صفحه'
              : 'اشتراک صفحه — نیاز به اجازهٔ میزبان',
          disabledCursor: SystemMouseCursors.forbidden,
          onPressed: !sharing && !canShare
              ? null
              : () => sharing
                    ? session.stopScreenShare()
                    : _pickScreen(context, ref),
        ),
      if (s.canEnd)
        DockButton(
          icon: ClassroomIcons.endClass,
          label: 'پایان کلاس',
          tint: t.danger,
          solid: true,
          showLabel: !narrow,
          onPressed: () => _confirmEnd(context, ref),
        )
      else if (s.showHand)
        HandToggle(
          raised: s.handUp,
          queuePosition: s.queue,
          showLabel: !narrow,
          onPressed: (s.handUp || s.canRaise) ? session.toggleHand : null,
        ),
      // A phone has no room for these in the dock: they move under "more".
      if (!narrow) ...[
        panel(PodKind.chat, ClassroomIcons.chat, 'گفتگو'),
        panel(PodKind.participants, ClassroomIcons.people, 'شرکت‌کنندگان'),
      ],
    ];

    final leave = LeaveButton(onPressed: session.leave, compact: narrow);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: Center(
        child: GlassBar(
          radius: 26,
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 8 : 10,
            vertical: narrow ? 8 : 9,
          ),
          child: narrow
              ? Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 6,
                  children: [
                    leave,
                    media(MediaDeviceKind.camera),
                    media(MediaDeviceKind.microphone),
                    ...tools,
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    leave,
                    const SizedBox(width: 10),
                    media(MediaDeviceKind.camera),
                    const SizedBox(width: 8),
                    media(MediaDeviceKind.microphone),
                    const BarDivider(height: 44),
                    for (final (i, tool) in tools.indexed) ...[
                      if (i > 0) const SizedBox(width: 4),
                      tool,
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _more(
    BuildContext context,
    WidgetRef ref, {
    required bool withPanels,
  }) async {
    final view = ref.read(classroomViewProvider);
    final appearance = ClassroomAppearance.maybeOf(context);
    final focus = StageFocusScope.maybeOf(context);
    final layout = view.room?.layout;
    final dark = appearance?.brightness == Brightness.dark;
    final action = await showGlassMenu<VoidCallback>(
      context: context,
      width: 230,
      entries: [
        if (withPanels && focus != null) ...[
          GlassMenuItem(
            value: () => focus.toggle(PodKind.chat, layout),
            label: 'گفتگو',
            icon: ClassroomIcons.chat,
            checked: focus.isFocused(PodKind.chat, layout),
          ),
          GlassMenuItem(
            value: () => focus.toggle(PodKind.participants, layout),
            label: 'شرکت‌کنندگان',
            icon: ClassroomIcons.people,
            checked: focus.isFocused(PodKind.participants, layout),
          ),
          const GlassMenuDivider(),
        ],
        if (view.can(Capability.layoutChange))
          GlassMenuItem(
            value: () =>
                showClassroomDialog<void>(context, const LayoutPickerSheet()),
            label: 'چیدمان',
            icon: ClassroomIcons.layout,
          ),
        if (view.can(Capability.participantsManage))
          GlassMenuItem(
            value: () =>
                showClassroomDialog<void>(context, const ClassSettingsSheet()),
            label: 'تنظیمات کلاس',
            icon: ClassroomIcons.settings,
          ),
        if (appearance != null) ...[
          if (view.can(Capability.layoutChange) ||
              view.can(Capability.participantsManage))
            const GlassMenuDivider(),
          GlassMenuItem(
            value: appearance.onToggle,
            label: dark ? 'پوستهٔ روشن' : 'پوستهٔ تیره',
            icon: dark ? ClassroomIcons.light : ClassroomIcons.dark,
          ),
        ],
      ],
    );
    action?.call();
  }

  Future<void> _pickDevice(
    BuildContext context,
    WidgetRef ref,
    MediaDeviceKind kind,
  ) async {
    final media = ref.read(classroomSessionProvider).media;
    final mic = kind == MediaDeviceKind.microphone;
    final devices = await media.devices(kind);
    if (!context.mounted) return;
    final chosen = await showGlassMenu<String>(
      context: context,
      width: 270,
      entries: [
        GlassMenuLabel(mic ? 'میکروفون' : 'دوربین'),
        if (devices.isEmpty)
          const GlassMenuItem(
            value: '',
            label: 'دستگاه را سیستم عامل انتخاب می‌کند',
            enabled: false,
          ),
        for (final d in devices)
          GlassMenuItem(
            value: d.id,
            label: d.label,
            icon: mic ? ClassroomIcons.mic : ClassroomIcons.camera,
            checked: d.selected,
          ),
      ],
    );
    if (chosen != null && chosen.isNotEmpty) {
      await media.selectDevice(kind, chosen);
    }
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
          icon: ClassroomIcons.endClass,
          iconColor: danger,
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'کلاس برای همه تمام می‌شود و ضبط آن به کتابخانه می‌رود.',
              ),
              const SizedBox(height: 18),
              GlowButton(
                label: 'پایان کلاس برای همه',
                color: danger,
                height: 46,
                onPressed: () => Navigator.of(context).pop(true),
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
      icon: ClassroomIcons.screenShare,
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
      icon: ClassroomIcons.settings,
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
