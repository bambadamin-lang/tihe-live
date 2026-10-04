import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';

/// A course in a list: the library and search results share it.
class CourseRow extends StatelessWidget {
  const CourseRow({required this.course, super.key});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final theme = Theme.of(context);
    final compact = context.windowSize.isCompact;

    return AppListRow(
      title: course.title,
      leading: Monogram(text: course.title),
      subtitle: Row(
        children: [
          Flexible(
            child: MetaLine(
              items: [
                if (course.teacherName != null) course.teacherName!,
                l10n.videoCount(JalaliFormat.toPersianDigits('${course.videoCount}')),
              ],
            ),
          ),
          // Shapes expectations before the student goes looking for a download button.
          if (!course.policy.allowDownload) ...[
            const SizedBox(width: AppSpace.x2),
            Tooltip(
              message: l10n.downloadNotAllowed,
              child: Icon(AppIcons.noDownload, size: 13, color: colors.textTertiary),
            ),
          ],
        ],
      ),
      trailing: _Progress(value: course.progress, compact: compact, theme: theme),
      showChevron: !compact,
      onTap: () => context.push('/course/${course.id}'),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.compact, required this.theme});

  final double value;
  final bool compact;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;

    if (value >= 1) {
      return AppBadge(
        label: l10n.courseCompleted,
        icon: AppIcons.completed,
        tone: BadgeTone.success,
      );
    }
    if (value <= 0) {
      return Text(
        l10n.notStarted,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
      );
    }

    final percent = Text(
      '${JalaliFormat.toPersianDigits('${(value * 100).round()}')}٪',
      style: theme.textTheme.labelSmall,
    );

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          percent,
          const SizedBox(width: AppSpace.x2),
          AppProgressRing(value: value),
        ],
      );
    }
    return SizedBox(
      width: 148,
      child: Row(
        children: [
          Expanded(child: AppProgressBar(value: value)),
          const SizedBox(width: AppSpace.x3),
          SizedBox(width: 30, child: percent),
        ],
      ),
    );
  }
}
