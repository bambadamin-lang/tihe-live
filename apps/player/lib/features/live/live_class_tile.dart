import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tihe_classroom/tihe_classroom.dart' as live;

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import 'classroom_launcher.dart';

/// Whether the signed-in user may start [liveClass]: its teacher, or an admin.
bool canHost(WidgetRef ref, live.LiveClass liveClass) {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthSignedIn) return false;
  final user = auth.session.user;
  return user.isAdmin || user.id == liveClass.teacherId;
}

/// What a class row says under its title: course, when, how long.
List<String> classMeta(BuildContext context, live.LiveClass liveClass, {String? courseTitle}) {
  final l10n = context.l10n;
  final at = liveClass.scheduledStartAt;
  return [
    if (courseTitle != null) courseTitle,
    if (at != null) JalaliFormat.schedule(at) else if (!liveClass.isLive) l10n.classNoTime,
    l10n.classMinutes(JalaliFormat.toPersianDigits('${liveClass.durationMinutes}')),
  ];
}

/// A class happening now: the one thing on the page that should be impossible to miss.
///
/// The join button is the card's whole purpose, so it is large, and on a phone it spans the card
/// rather than squeezing the title.
class LiveNowCard extends ConsumerStatefulWidget {
  const LiveNowCard({required this.liveClass, this.courseTitle, super.key});

  final live.LiveClass liveClass;
  final String? courseTitle;

  @override
  ConsumerState<LiveNowCard> createState() => _LiveNowCardState();
}

class _LiveNowCardState extends ConsumerState<LiveNowCard> {
  bool _joining = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    await joinLiveClass(context, sessionId: widget.liveClass.liveSessionId!);
    if (mounted) setState(() => _joining = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;
    final compact = context.windowSize.isCompact;
    final c = widget.liveClass;
    final mine = canHost(ref, c);

    final button = AppButton.primary(
      label: _joining ? l10n.joiningClass : l10n.joinClass,
      icon: AppIcons.start,
      size: AppButtonSize.large,
      loading: _joining,
      expand: compact,
      onPressed: _join,
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            live.PulsingDot(color: colors.danger),
            const SizedBox(width: AppSpace.x2),
            Text(
              l10n.liveNowBadge,
              style: theme.textTheme.labelMedium?.copyWith(color: colors.danger),
            ),
            if (mine) ...[
              const SizedBox(width: AppSpace.x2),
              AppBadge(label: l10n.yourClass, tone: BadgeTone.accent),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.x2),
        Text(c.title, style: theme.textTheme.titleMedium, maxLines: 2),
        const SizedBox(height: 2),
        MetaLine(items: classMeta(context, c, courseTitle: widget.courseTitle), maxLines: 2),
      ],
    );

    return live.Glass(
      radius: 20,
      padding: const EdgeInsets.all(AppSpace.x5),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: AppSpace.x4),
                button,
              ],
            )
          : Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: AppSpace.x4),
                button,
              ],
            ),
    );
  }
}

/// A class that is not running: when it is, and for its teacher, the button that starts it.
class ClassRow extends ConsumerStatefulWidget {
  const ClassRow({required this.liveClass, this.courseTitle, super.key});

  final live.LiveClass liveClass;
  final String? courseTitle;

  @override
  ConsumerState<ClassRow> createState() => _ClassRowState();
}

class _ClassRowState extends ConsumerState<ClassRow> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    await startLiveClass(context, classId: widget.liveClass.id);
    if (mounted) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = widget.liveClass;
    final mine = canHost(ref, c);

    return AppListRow(
      title: c.title,
      leading: const IconTile(icon: AppIcons.liveClass),
      subtitle: MetaLine(
        items: classMeta(context, c, courseTitle: widget.courseTitle),
        maxLines: 2,
      ),
      trailing: mine
          ? AppButton(
              label: _starting ? l10n.startingClass : l10n.startClass,
              icon: AppIcons.start,
              loading: _starting,
              onPressed: _start,
            )
          : AppBadge(label: l10n.classNotStarted),
    );
  }
}
