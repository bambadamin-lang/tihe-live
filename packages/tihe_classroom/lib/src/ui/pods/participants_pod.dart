import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import 'people.dart';
import 'person_actions.dart';

export 'person_actions.dart' show PermissionsDialog;

/// Everyone in the class: role tag, mic and camera state, raised hand, and —
/// for managers — the actions they may take on each person (docs/11 §3–4).
class ParticipantsPod extends ConsumerWidget {
  const ParticipantsPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The list watches only who is in it and in what order; each card watches its own person.
    final people = ref
        .watch(
          classroomViewProvider.select((v) {
            final room = v.room;
            if (room == null) return null;
            final sorted = room.participants.values.toList()
              ..sort((a, b) {
                if (a.online != b.online) return a.online ? -1 : 1;
                return b.role.rank.compareTo(a.role.rank);
              });
            return ListValue([for (final p in sorted) p.userId]);
          }),
        )
        ?.items;
    if (people == null) return const SizedBox.shrink();
    return ListView.builder(
      padding: const EdgeInsets.all(2),
      itemCount: people.length,
      itemBuilder: (context, i) =>
          _Card(key: ValueKey(people[i]), userId: people[i]),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(
      classroomViewProvider.select((v) {
        final p = v.room?.participants[userId];
        if (p == null) return null;
        final media = v.media.of(userId);
        return (
          // Participant states are immutable and replaced when they change.
          p: p,
          micOn: media.micOn,
          cameraOn: media.cameraOn,
          isMe: userId == v.userId,
        );
      }),
    );
    if (c == null) return const SizedBox.shrink();
    final t = ClassroomTheme.of(context);
    final (:p, :micOn, :cameraOn, :isMe) = c;
    return Opacity(
      opacity: p.online ? 1 : 0.5,
      child: PersonRow(
        alert: p.capturing ? t.danger : null,
        child: Row(
          children: [
            Avatar(userId: p.userId, name: p.name, size: 34),
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
                            fontWeight: FontWeight.w600,
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
              Icon(ClassroomIcons.hand, size: 17, color: t.warning),
              const SizedBox(width: 10),
            ],
            Icon(
              micOn ? ClassroomIcons.mic : ClassroomIcons.micOff,
              size: 17,
              color: micOn ? t.success : t.textTertiary,
            ),
            const SizedBox(width: 10),
            Icon(
              cameraOn ? ClassroomIcons.camera : ClassroomIcons.cameraOff,
              size: 17,
              color: cameraOn ? t.accentText : t.textTertiary,
            ),
            const SizedBox(width: 4),
            ParticipantMenuButton(userId: p.userId),
          ],
        ),
      ),
    );
  }
}
