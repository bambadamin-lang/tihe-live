import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import '../theme/menu.dart';
import '../theme/motion.dart';
import 'people.dart';
import 'person_actions.dart';

/// The raised-hand queue, in the order the server received them. Managers give the floor
/// (with or without camera) or lower hands from here.
class HandsPod extends ConsumerStatefulWidget {
  const HandsPod({super.key});

  @override
  ConsumerState<HandsPod> createState() => _HandsPodState();
}

class _HandsPodState extends ConsumerState<HandsPod> {
  /// Hands already up when the pod opened don't replay their arrival.
  SeenSet? _seen;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final view = ref.watch(classroomViewProvider);
    final hands = view.room?.raisedHands ?? const <ParticipantState>[];
    // A hand is one raise, not one person: lowering and raising again arrives again.
    String raise(ParticipantState p) => '${p.userId}:${p.hand!.raisedSeq}';
    final seen = _seen ??= SeenSet(hands.map(raise));
    final canManage = view.can(Capability.participantsManage);
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
                        size: 24,
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
                    return Appear(
                      key: ValueKey(raise(p)),
                      animate: seen.isNew(raise(p)),
                      offset: const Offset(0, 10),
                      scale: 0.96,
                      child: PersonRow(
                        child: Row(
                          children: [
                            Tooltip(
                              message: 'نفر ${toPersianDigits(i + 1)} در صف',
                              child: Icon(
                                ClassroomIcons.hand,
                                size: 20,
                                color: t.warning,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Avatar(userId: p.userId, name: p.name, size: 34),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: t.text,
                                ),
                              ),
                            ),
                            if (canManage) ...[
                              GlassIconButton(
                                tooltip: 'اجازهٔ صحبت',
                                icon: ClassroomIcons.mic,
                                color: t.success,
                                size: 32,
                                iconSize: 18,
                                onPressed: () => session.send(
                                  GiveFloor(p.userId, video: false),
                                ),
                              ),
                              GlassIconButton(
                                tooltip: 'اجازهٔ صحبت با تصویر',
                                icon: ClassroomIcons.camera,
                                color: t.accentText,
                                size: 32,
                                iconSize: 18,
                                onPressed: () => session.send(
                                  GiveFloor(p.userId, video: true),
                                ),
                              ),
                              ParticipantMenuButton(userId: p.userId),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (canManage && hands.isNotEmpty) ...[
          Divider(height: 1, color: t.hairline),
          const SizedBox(height: 4),
          Builder(
            builder: (context) => GlassPressable(
              onTap: () async {
                final first = hands.first.userId;
                final command = await showGlassMenu<ClassroomCommand>(
                  context: context,
                  width: 260,
                  entries: [
                    GlassMenuItem(
                      value: GiveFloor(first, video: false),
                      label: 'اجازهٔ صحبت به نفر اول',
                      icon: ClassroomIcons.mic,
                    ),
                    GlassMenuItem(
                      value: GiveFloor(first, video: true),
                      label: 'اجازهٔ صحبت با تصویر به نفر اول',
                      icon: ClassroomIcons.camera,
                    ),
                    const GlassMenuDivider(),
                    const GlassMenuItem(
                      value: LowerAllHands(),
                      label: 'پایین آوردن همهٔ دست‌ها',
                      icon: ClassroomIcons.lowerAll,
                    ),
                  ],
                );
                if (command != null) await session.send(command);
              },
              semanticLabel: 'پاسخ دادن به دست‌ها',
              radius: 10,
              builder: (context, s) => AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: s.hovered ? t.glassHover : Colors.transparent,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'پاسخ دادن به دست‌ها',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      ClassroomIcons.chevronDown,
                      size: 16,
                      color: t.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
