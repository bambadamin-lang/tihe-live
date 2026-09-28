import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import 'people.dart';

/// The raised-hand queue, numbered in the order the server received them. Managers
/// give the floor (with or without camera) or lower hands from here.
class HandsPod extends ConsumerWidget {
  const HandsPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ClassroomTheme.of(context);
    // The queue and the right to manage it — not the rest of the class.
    final hands = ref
        .watch(
          classroomViewProvider.select(
            (v) => ListSlice(v.room?.raisedHands ?? const <ParticipantState>[]),
          ),
        )
        .items;
    final canManage = ref.watch(
      classroomViewProvider.select((v) => v.can(Capability.participantsManage)),
    );
    final session = ref.read(classroomSessionProvider);
    return Column(
      children: [
        Expanded(
          child: hands.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ClassroomIcons.hand,
                        size: 22,
                        color: t.textTertiary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'دستی بالا نیست',
                        style: TextStyle(color: t.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(2),
                  itemCount: hands.length,
                  itemBuilder: (context, i) {
                    final p = hands[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 4, 6),
                      decoration: BoxDecoration(
                        color: t.glassHover,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.hairline),
                      ),
                      child: Row(
                        children: [
                          _Ticket(number: i + 1),
                          const SizedBox(width: 10),
                          Avatar(userId: p.userId, name: p.name, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13.5,
                                color: t.text,
                              ),
                            ),
                          ),
                          if (canManage) ...[
                            GlassIconButton(
                              tooltip: 'اجازهٔ صحبت',
                              icon: ClassroomIcons.mic,
                              color: t.success,
                              onPressed: () => session.send(
                                GiveFloor(p.userId, video: false),
                              ),
                            ),
                            GlassIconButton(
                              tooltip: 'اجازهٔ صحبت با تصویر',
                              icon: ClassroomIcons.camera,
                              color: t.accentText,
                              onPressed: () => session.send(
                                GiveFloor(p.userId, video: true),
                              ),
                            ),
                            GlassIconButton(
                              tooltip: 'پایین آوردن دست',
                              icon: ClassroomIcons.close,
                              onPressed: () =>
                                  session.send(LowerHand(p.userId)),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (canManage && hands.length > 1)
          TextButton.icon(
            onPressed: () => session.send(const LowerAllHands()),
            icon: const Icon(ClassroomIcons.lowerAll, size: 16),
            label: const Text('پایین آوردن همهٔ دست‌ها'),
          ),
      ],
    );
  }
}

class _Ticket extends StatelessWidget {
  const _Ticket({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.warningSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        toPersianDigits(number),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
          color: t.warning,
        ),
      ),
    );
  }
}
