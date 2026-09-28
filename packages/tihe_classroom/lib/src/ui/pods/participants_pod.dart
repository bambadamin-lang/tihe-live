import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../state/classroom_session.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import '../theme/transitions.dart';
import 'people.dart';

/// Everyone in the class: role tag, mic and camera state, raised hand, and —
/// for managers — the actions they may take on each person (docs/11 §3–4).
class ParticipantsPod extends ConsumerWidget {
  const ParticipantsPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ClassroomTheme.of(context);
    final view = ref.watch(classroomViewProvider);
    final room = view.room;
    if (room == null) return const SizedBox.shrink();
    final people = room.participants.values.toList()
      ..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return b.role.rank.compareTo(a.role.rank);
      });
    return ListView.separated(
      padding: const EdgeInsets.all(2),
      itemCount: people.length,
      separatorBuilder: (_, _) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 48),
        child: Divider(color: t.hairline),
      ),
      itemBuilder: (context, i) => _Card(participant: people[i], view: view),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.participant, required this.view});

  final ParticipantState participant;
  final ClassroomView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ClassroomTheme.of(context);
    final p = participant;
    final media = view.media.of(p.userId);
    final me = view.me;
    final isMe = p.userId == view.userId;
    final canManage =
        me != null &&
        !isMe &&
        me.can(Capability.participantsManage) &&
        me.role.outranks(p.role);
    final canAssign = me != null && !isMe && me.can(Capability.rolesAssign);
    return Opacity(
      opacity: p.online ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 7, 0, 7),
        decoration: p.capturing
            ? BoxDecoration(
                color: t.dangerSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.danger.withValues(alpha: 0.5)),
              )
            : null,
        child: Row(
          children: [
            Avatar(userId: p.userId, name: p.name, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isMe ? '${p.name} (شما)' : p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13.5,
                            color: t.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      RolePin(role: p.role),
                    ],
                  ),
                  if (p.capturing)
                    Text(
                      'در حال ضبط صفحه — نمای او سانسور شده است',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else if (p.floor)
                    Text(
                      'اجازهٔ صحبت دارد',
                      style: TextStyle(fontSize: 11.5, color: t.success),
                    ),
                ],
              ),
            ),
            if (p.hand != null) ...[
              Icon(ClassroomIcons.hand, size: 15, color: t.warning),
              const SizedBox(width: 8),
            ],
            Icon(
              media.micOn ? ClassroomIcons.mic : ClassroomIcons.micOff,
              size: 15,
              color: media.micOn ? t.success : t.textTertiary,
            ),
            const SizedBox(width: 6),
            Icon(
              media.cameraOn ? ClassroomIcons.camera : ClassroomIcons.cameraOff,
              size: 15,
              color: media.cameraOn ? t.success : t.textTertiary,
            ),
            if (canManage || canAssign)
              _Actions(
                participant: p,
                canManage: canManage,
                canAssign: canAssign,
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.participant,
    required this.canManage,
    required this.canAssign,
  });

  final ParticipantState participant;
  final bool canManage;
  final bool canAssign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(classroomSessionProvider);
    final p = participant;
    final danger = ClassroomTheme.of(context).danger;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'کارها',
      icon: const Icon(ClassroomIcons.more, size: 16),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        if (canManage) ...[
          if (!p.floor) ...[
            PopupMenuItem(
              value: () => session.send(GiveFloor(p.userId, video: false)),
              child: const Text('اجازهٔ صحبت'),
            ),
            PopupMenuItem(
              value: () => session.send(GiveFloor(p.userId, video: true)),
              child: const Text('اجازهٔ صحبت با تصویر'),
            ),
          ] else
            PopupMenuItem(
              value: () => session.send(TakeFloor(p.userId)),
              child: const Text('پس گرفتن اجازهٔ صحبت'),
            ),
          if (p.hand != null)
            PopupMenuItem(
              value: () => session.send(LowerHand(p.userId)),
              child: const Text('پایین آوردن دست'),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: () =>
                session.send(MuteParticipant(p.userId, MediaSource.audio)),
            child: const Text('قطع میکروفون'),
          ),
          PopupMenuItem(
            value: () =>
                session.send(MuteParticipant(p.userId, MediaSource.video)),
            child: const Text('خاموش کردن دوربین'),
          ),
          PopupMenuItem(
            value: () =>
                session.send(MuteParticipant(p.userId, MediaSource.screen)),
            child: const Text('توقف اشتراک صفحه'),
          ),
          PopupMenuItem(
            value: () => showGlassDialog<void>(
              context: context,
              builder: (_) => UncontrolledProviderScope(
                container: ProviderScope.containerOf(context),
                child: PermissionsDialog(userId: p.userId),
              ),
            ),
            child: const Text('اجازه‌ها…'),
          ),
        ],
        if (canAssign) ...[
          const PopupMenuDivider(),
          for (final role in assignableRoles.where((r) => r != p.role))
            PopupMenuItem(
              value: () => session.send(SetRole(p.userId, role)),
              child: Text('نقش: ${role.labelFa}'),
            ),
        ],
        if (canManage) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: () => _confirmRemove(context, session),
            child: Text('خارج کردن از کلاس', style: TextStyle(color: danger)),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    ClassroomSession session,
  ) async {
    final danger = ClassroomTheme.of(context).danger;
    final sure = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassSheet(
        title: 'خارج کردن ${participant.name}',
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تا پایان این جلسه نمی‌تواند دوباره وارد شود.'),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('خارج کن'),
            ),
          ],
        ),
      ),
    );
    if (sure ?? false) {
      await session.send(RemoveParticipant(participant.userId));
    }
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
      width: 400,
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
    );
  }
}
