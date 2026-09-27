import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/materials.dart';
import 'people.dart';

/// The raised-hand queue, as numbered tickets in the order the server received them. Managers
/// give the floor (with or without camera) or lower hands from here.
class HandsPod extends ConsumerWidget {
  const HandsPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ClassroomTheme.of(context);
    final view = ref.watch(classroomViewProvider);
    final hands = view.room?.raisedHands ?? const <ParticipantState>[];
    final canManage = view.can(Capability.participantsManage);
    final session = ref.read(classroomSessionProvider);
    return CustomPaint(
      painter: PaperPainter(t, radius: 10),
      child: Column(
        children: [
          Expanded(
            child: hands.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.back_hand_outlined,
                          size: 28,
                          color: t.paperEdge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'دستی بالا نیست',
                          style: TextStyle(color: t.inkSoft),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: hands.length,
                    itemBuilder: (context, i) {
                      final p = hands[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            right: BorderSide(color: t.ledAmber, width: 4),
                          ),
                        ),
                        child: Row(
                          children: [
                            _Ticket(number: i + 1),
                            const SizedBox(width: 8),
                            Avatar(userId: p.userId, name: p.name, size: 26),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: t.ink,
                                ),
                              ),
                            ),
                            if (canManage) ...[
                              IconButton(
                                tooltip: 'اجازهٔ صحبت',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.mic, color: t.ledGreen),
                                onPressed: () => session.send(
                                  GiveFloor(p.userId, video: false),
                                ),
                              ),
                              IconButton(
                                tooltip: 'اجازهٔ صحبت با تصویر',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.videocam, color: t.pinTeal),
                                onPressed: () => session.send(
                                  GiveFloor(p.userId, video: true),
                                ),
                              ),
                              IconButton(
                                tooltip: 'پایین آوردن دست',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.pan_tool_alt_outlined,
                                  color: t.inkSoft,
                                ),
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
              icon: const Icon(Icons.clear_all),
              label: const Text('پایین آوردن همهٔ دست‌ها'),
            ),
        ],
      ),
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
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: t.brassPlate,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: t.brassDark),
      ),
      child: Text(
        toPersianDigits(number),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF3A2A10),
        ),
      ),
    );
  }
}
