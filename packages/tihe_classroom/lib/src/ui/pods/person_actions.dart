import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../state/classroom_session.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import '../theme/menu.dart';
import '../theme/transitions.dart';

/// What the viewer may do to someone else (docs/11 §3–4), as a "⋯" button that opens a glass
/// menu. Renders nothing when there is nothing they may do. The server checks every command
/// again; this only keeps the menu honest.
class ParticipantMenuButton extends ConsumerWidget {
  const ParticipantMenuButton({
    super.key,
    required this.userId,
    this.icon = ClassroomIcons.moreHorizontal,
    this.floating = false,
  });

  final String userId;
  final IconData icon;

  /// Over video: a dark backing so it can be seen.
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only what decides whether there is a menu: it sits in every row, so it must not rebuild
    // on every change in the class. The menu reads the person when it opens.
    final s = ref.watch(
      classroomViewProvider.select((v) {
        final p = v.room?.participants[userId];
        final me = v.me;
        if (p == null || me == null || userId == v.userId) return null;
        final canManage =
            me.can(Capability.participantsManage) && me.role.outranks(p.role);
        final canAssign = me.can(Capability.rolesAssign);
        return canManage || canAssign
            ? (canManage: canManage, canAssign: canAssign)
            : null;
      }),
    );
    if (s == null) return const SizedBox.shrink();
    return Builder(
      builder: (context) => GlassIconButton(
        icon: icon,
        tooltip: 'کارها',
        size: floating ? 34 : 30,
        iconSize: 17,
        radius: 10,
        fill: floating ? const Color(0x990A1122) : null,
        color: floating ? Colors.white.withValues(alpha: 0.85) : null,
        onPressed: () {
          final p = ref.read(classroomViewProvider).room?.participants[userId];
          if (p != null) _open(context, ref, p, s.canManage, s.canAssign);
        },
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    ParticipantState p,
    bool canManage,
    bool canAssign,
  ) async {
    final session = ref.read(classroomSessionProvider);
    final action = await showGlassMenu<VoidCallback>(
      context: context,
      width: 250,
      entries: [
        GlassMenuLabel(p.name),
        if (canManage) ...[
          if (!p.floor) ...[
            GlassMenuItem(
              value: () => session.send(GiveFloor(p.userId, video: false)),
              label: 'اجازهٔ صحبت',
              icon: ClassroomIcons.mic,
            ),
            GlassMenuItem(
              value: () => session.send(GiveFloor(p.userId, video: true)),
              label: 'اجازهٔ صحبت با تصویر',
              icon: ClassroomIcons.camera,
            ),
          ] else
            GlassMenuItem(
              value: () => session.send(TakeFloor(p.userId)),
              label: 'پس گرفتن اجازهٔ صحبت',
              icon: ClassroomIcons.micOff,
            ),
          if (p.hand != null)
            GlassMenuItem(
              value: () => session.send(LowerHand(p.userId)),
              label: 'پایین آوردن دست',
              icon: ClassroomIcons.lowerHand,
            ),
          const GlassMenuDivider(),
          GlassMenuItem(
            value: () =>
                session.send(MuteParticipant(p.userId, MediaSource.audio)),
            label: 'قطع میکروفون',
            icon: ClassroomIcons.micOff,
          ),
          GlassMenuItem(
            value: () =>
                session.send(MuteParticipant(p.userId, MediaSource.video)),
            label: 'خاموش کردن دوربین',
            icon: ClassroomIcons.cameraOff,
          ),
          GlassMenuItem(
            value: () =>
                session.send(MuteParticipant(p.userId, MediaSource.screen)),
            label: 'توقف اشتراک صفحه',
            icon: ClassroomIcons.screenShareOff,
          ),
          GlassMenuItem(
            value: () => showGlassDialog<void>(
              context: context,
              barrierColor: ClassroomTheme.of(context).scrim,
              builder: (_) => UncontrolledProviderScope(
                container: ProviderScope.containerOf(context),
                child: PermissionsDialog(userId: p.userId),
              ),
            ),
            label: 'اجازه‌ها…',
            icon: ClassroomIcons.settings,
          ),
        ],
        if (canAssign) ...[
          const GlassMenuDivider(),
          const GlassMenuLabel('نقش'),
          for (final role in assignableRoles)
            GlassMenuItem(
              value: () {
                if (role != p.role) session.send(SetRole(p.userId, role));
              },
              label: role.labelFa,
              checked: role == p.role,
            ),
        ],
        if (canManage) ...[
          const GlassMenuDivider(),
          GlassMenuItem(
            value: () => _confirmRemove(context, session, p),
            label: 'خارج کردن از کلاس',
            icon: ClassroomIcons.leave,
            danger: true,
          ),
        ],
      ],
    );
    action?.call();
  }

  Future<void> _confirmRemove(
    BuildContext context,
    ClassroomSession session,
    ParticipantState p,
  ) async {
    final t = ClassroomTheme.of(context);
    final sure = await showGlassDialog<bool>(
      context: context,
      barrierColor: t.scrim,
      builder: (context) => GlassSheet(
        title: 'خارج کردن ${p.name}',
        icon: ClassroomIcons.leave,
        iconColor: t.danger,
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تا پایان این جلسه نمی‌تواند دوباره وارد شود.'),
            const SizedBox(height: 18),
            GlowButton(
              label: 'خارج کن',
              color: t.danger,
              height: 46,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (sure ?? false) await session.send(RemoveParticipant(p.userId));
  }
}

/// Grant or revoke one person's individual capabilities. The server still checks each change:
/// nobody grants what they do not hold.
class PermissionsDialog extends ConsumerWidget {
  const PermissionsDialog({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(
      classroomViewProvider.select((v) => v.room?.participants[userId]),
    );
    final session = ref.read(classroomSessionProvider);
    if (p == null) return const SizedBox.shrink();
    return GlassSheet(
      title: 'اجازه‌های ${p.name}',
      icon: ClassroomIcons.settings,
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final cap in grantableCapabilities)
              SwitchListTile(
                dense: true,
                title: Text(cap.labelFa),
                value: p.can(cap),
                onChanged: (on) => session.send(
                  on ? GrantCaps(userId, [cap]) : RevokeCaps(userId, [cap]),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => session.send(ResetCaps(userId)),
                child: const Text('بازگشت به اجازه‌های پیش‌فرض'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
