import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../state/classroom_session.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/materials.dart';
import '../theme/skeuo.dart';
import 'people.dart';

/// Everyone in the class as index cards: role pin, mic and camera lamps, raised hand, and —
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
    return CustomPaint(
      painter: PaperPainter(t, radius: 10),
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(height: 5),
        itemBuilder: (context, i) => _Card(participant: people[i], view: view),
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(8),
          border: p.capturing ? Border.all(color: t.ledRed, width: 2) : null,
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Avatar(userId: p.userId, name: p.name, size: 30),
            const SizedBox(width: 8),
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
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: t.ink,
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
                        fontSize: 11,
                        color: t.ledRed,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (p.floor)
                    Text(
                      'اجازهٔ صحبت دارد',
                      style: TextStyle(fontSize: 11, color: t.pinTeal),
                    ),
                ],
              ),
            ),
            if (p.hand != null)
              Icon(Icons.back_hand, size: 17, color: t.ledAmber),
            const SizedBox(width: 6),
            Icon(
              media.micOn ? Icons.mic : Icons.mic_off,
              size: 16,
              color: media.micOn ? t.ledGreen : t.inkSoft,
            ),
            Icon(
              media.cameraOn ? Icons.videocam : Icons.videocam_off,
              size: 16,
              color: media.cameraOn ? t.ledGreen : t.inkSoft,
            ),
            if (canManage || canAssign)
              _Actions(
                participant: p,
                canManage: canManage,
                canAssign: canAssign,
              ),
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
    return PopupMenuButton<VoidCallback>(
      tooltip: 'کارها',
      icon: const Icon(Icons.more_vert, size: 18),
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
            value: () => showDialog<void>(
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
            child: const Text(
              'خارج کردن از کلاس',
              style: TextStyle(color: Color(0xFFB3261E)),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    ClassroomSession session,
  ) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => PaperSheet(
        title: 'خارج کردن ${participant.name}',
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تا پایان این جلسه نمی‌تواند دوباره وارد شود.'),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB3261E),
              ),
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
    return PaperSheet(
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
