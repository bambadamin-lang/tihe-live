import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../data/gateway_client.dart';
import '../../data/media.dart';
import '../../domain/persian.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/skeuo.dart';
import 'layout_picker.dart';

/// Opens a dialog that still sees the classroom's providers (dialogs live above the page's
/// ProviderScope in the widget tree).
Future<T?> showClassroomDialog<T>(BuildContext context, Widget child) =>
    showDialog<T>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    );

/// The brass title plate, the LIVE and REC lamps, and the connection state.
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
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final plate = BrassPlate(
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
    );
    final classLamps = [
      if (startedAt != null) _LiveClock(startedAt: DateTime.parse(startedAt)),
      if (recording)
        _Lamp(
          led: PulsingLed(color: t.ledRed),
          label: narrow ? 'ضبط' : 'در حال ضبط',
        ),
    ];
    final roomLamps = [
      if (capturing > 0)
        Tooltip(
          message:
              'شرکت‌کنندگانی که در حال ضبط صفحه‌اند؛ نمای آن‌ها سانسور شده است',
          child: _Lamp(
            led: Led(color: t.ledRed),
            label: '${toPersianDigits(capturing)} ضبط',
          ),
        ),
      _Lamp(
        led: Icon(Icons.people_alt, size: 16, color: t.paperHigh),
        label: toPersianDigits(online),
      ),
      _ConnectionLamp(status: status),
    ];
    // Wide: class lamps by the title, room lamps at the far end. Narrow: they wrap.
    final lamps = narrow
        ? Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [...classLamps, ...roomLamps],
          )
        : Row(
            children: [
              for (final lamp in classLamps)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: lamp,
                ),
              const Spacer(),
              for (final lamp in roomLamps)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 10),
                  child: lamp,
                ),
            ],
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      // A phone has no room for the plate beside the lamps: it gets its own row.
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [plate, const SizedBox(height: 6), lamps],
            )
          : Row(
              children: [
                Flexible(child: plate),
                const SizedBox(width: 12),
                Expanded(child: lamps),
              ],
            ),
    );
  }
}

class _Lamp extends StatelessWidget {
  const _Lamp({required this.led, required this.label});

  final Widget led;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        led,
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF3EAD6),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
  late final Timer _timer = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Lamp(
    led: Led(color: ClassroomTheme.of(context).ledGreen),
    label: 'زنده  ${elapsedClock(DateTime.now().difference(widget.startedAt))}',
  );
}

class _ConnectionLamp extends StatelessWidget {
  const _ConnectionLamp({required this.status});
  final GatewayStatus status;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final (color, label) = switch (status) {
      GatewayStatus.online => (t.ledGreen, 'متصل'),
      GatewayStatus.connecting => (t.ledAmber, 'در حال اتصال'),
      GatewayStatus.reconnecting => (t.ledAmber, 'اتصال دوباره…'),
      GatewayStatus.closed => (t.ledRed, 'قطع'),
    };
    return _Lamp(
      led: Led(color: color, size: 8),
      label: label,
    );
  }
}

/// The metal control bar: microphone, camera and screen rockers, the hand paddle, and the
/// host's layout, settings and end-of-class buttons.
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
      RockerSwitch(
        on: local?.micOn ?? false,
        locked: !view.can(Capability.publishAudio),
        icon: Icons.mic,
        offIcon: Icons.mic_off,
        label: 'میکروفون',
        onPressed: session.toggleMicrophone,
      ),
      RockerSwitch(
        on: local?.cameraOn ?? false,
        locked: !view.can(Capability.publishVideo),
        icon: Icons.videocam,
        offIcon: Icons.videocam_off,
        label: 'دوربین',
        onPressed: session.toggleCamera,
      ),
      if (!narrow || view.can(Capability.publishScreen))
        RockerSwitch(
          on: local?.screenOn ?? false,
          locked: !view.can(Capability.publishScreen),
          icon: Icons.screen_share,
          offIcon: Icons.stop_screen_share_outlined,
          label: 'اشتراک صفحه',
          onPressed: () => (local?.screenOn ?? false)
              ? session.stopScreenShare()
              : _pickScreen(context, ref),
        ),
      if (me == null || me.role.rank < ClassRole.cohost.rank)
        HandPaddle(
          raised: me?.hand != null,
          queuePosition: position >= 0 ? position + 1 : null,
          onPressed: (me?.hand != null || view.can(Capability.handRaise))
              ? session.toggleHand
              : null,
        ),
    ];

    final host = [
      if (view.can(Capability.layoutChange))
        DomeButton(
          icon: Icons.dashboard_customize_outlined,
          label: 'چیدمان',
          color: t.pinNavy,
          showLabel: !narrow,
          onPressed: () =>
              showClassroomDialog<void>(context, const LayoutPickerSheet()),
        ),
      if (view.can(Capability.participantsManage))
        DomeButton(
          icon: Icons.tune,
          label: 'تنظیمات کلاس',
          color: t.pinTeal,
          showLabel: !narrow,
          onPressed: () =>
              showClassroomDialog<void>(context, const ClassSettingsSheet()),
        ),
      if (view.can(Capability.classEnd))
        DomeButton(
          icon: Icons.stop_circle_outlined,
          label: 'پایان کلاس',
          color: const Color(0xFF9E2A22),
          showLabel: !narrow,
          onPressed: () => _confirmEnd(context, ref),
        ),
      DomeButton(
        icon: Icons.logout,
        label: 'خروج',
        color: const Color(0xFF6B5B47),
        showLabel: !narrow,
        onPressed: session.leave,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: MetalBar(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: narrow
            ? Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [...media, ...host],
              )
            : Row(
                children: [
                  for (final w in media)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: w,
                    ),
                  const Spacer(),
                  for (final w in host)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: w,
                    ),
                ],
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
    final sure = await showClassroomDialog<bool>(
      context,
      Builder(
        builder: (context) => PaperSheet(
          title: 'پایان کلاس',
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'کلاس برای همه تمام می‌شود و ضبط آن به کتابخانه می‌رود.',
              ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9E2A22),
                ),
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
    return PaperSheet(
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
            InkWell(
              onTap: () => Navigator.of(context).pop(s),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.screenGlass,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.paperEdge),
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
                                  ? Icons.desktop_windows_outlined
                                  : Icons.web_asset,
                              color: t.paperLow,
                              size: 36,
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.isScreen ? 'کل صفحه — ${s.name}' : s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
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
    return PaperSheet(
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
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => session.send(const MuteAll()),
                  icon: const Icon(Icons.mic_off),
                  label: const Text('بی‌صدا کردن همه'),
                ),
                OutlinedButton.icon(
                  onPressed: () => session.send(const LowerAllHands()),
                  icon: const Icon(Icons.clear_all),
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
