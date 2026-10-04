import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';

/// A course: its sections, its sessions, and what the student has watched.
class CourseScreen extends ConsumerWidget {
  const CourseScreen({required this.courseId, super.key});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseProvider(courseId));
    final back = BackTarget(label: context.l10n.libraryTitle, fallbackLocation: '/library');

    return course.when(
      skipLoadingOnRefresh: true,
      loading: () => _CourseSkeleton(back: back),
      error: (error, _) => AppPage(
        back: back,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorView(error: error, onRetry: () => ref.invalidate(courseProvider(courseId))),
          ),
        ],
      ),
      data: (data) => _CourseBody(
        course: data,
        back: back,
        onRefresh: () async => ref.invalidate(courseProvider(courseId)),
      ),
    );
  }
}

class _CourseBody extends StatelessWidget {
  const _CourseBody({required this.course, required this.back, required this.onRefresh});

  final Course course;
  final BackTarget back;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasSections = course.sections.isNotEmpty;

    return AppPage(
      back: back,
      maxWidth: 880,
      onRefresh: onRefresh,
      header: _CourseHeader(course: course),
      slivers: [
        if (course.allVideos.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.x12),
              child: EmptyState(icon: AppIcons.sessions, title: l10n.courseEmpty),
            ),
          ),
        for (final section in course.sections)
          if (section.videos.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(title: section.title, meta: _sectionMeta(l10n, section.videos)),
            ),
            BleedSliver(
              sliver: SliverList.builder(
                itemCount: section.videos.length,
                itemBuilder: (_, index) => _SessionRow(
                  video: section.videos[index],
                  index: index + 1,
                  allowDownload: course.policy.allowDownload,
                ),
              ),
            ),
          ],
        if (course.looseVideos.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: hasSections ? l10n.otherSessions : l10n.courseContent,
              meta: _sectionMeta(l10n, course.looseVideos),
            ),
          ),
          BleedSliver(
            sliver: SliverList.builder(
              itemCount: course.looseVideos.length,
              itemBuilder: (_, index) => _SessionRow(
                video: course.looseVideos[index],
                index: index + 1,
                allowDownload: course.policy.allowDownload,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _sectionMeta(AppLocalizations l10n, List<Video> videos) {
    final total = videos.fold(Duration.zero, (sum, v) => sum + v.duration);
    return [
      l10n.videoCount(JalaliFormat.toPersianDigits('${videos.length}')),
      if (total > Duration.zero) JalaliFormat.spokenDuration(total),
    ].join('  ·  ');
  }
}

class _CourseHeader extends StatelessWidget {
  const _CourseHeader({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final theme = Theme.of(context);
    final compact = context.windowSize.isCompact;
    final next = course.nextVideo;
    final total = course.allVideos.length;

    final action = next == null
        ? null
        : AppButton.primary(
            label: next.hasProgress
                ? l10n.resume
                : course.progress > 0
                ? l10n.continueAction
                : l10n.startCourse,
            icon: AppIcons.play,
            expand: compact,
            size: compact ? AppButtonSize.large : AppButtonSize.medium,
            onPressed: () => context.push('/watch/${next.id}'),
          );

    return PageHeader(
      title: course.title,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (course.teacherName != null)
            Text(
              course.teacherName!,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          if (course.description != null) ...[
            const SizedBox(height: AppSpace.x3),
            _Description(text: course.description!),
          ],
        ],
      ),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.x2,
            runSpacing: AppSpace.x2,
            children: [
              AppBadge(
                icon: AppIcons.sessions,
                label: l10n.videoCount(JalaliFormat.toPersianDigits('${course.videoCount}')),
              ),
              if (course.totalDuration > Duration.zero)
                AppBadge(
                  icon: AppIcons.duration,
                  label: JalaliFormat.spokenDuration(course.totalDuration),
                ),
              if (!course.policy.allowDownload)
                AppBadge(icon: AppIcons.noDownload, label: l10n.downloadNotAllowed),
            ],
          ),
          const SizedBox(height: AppSpace.x5),
          Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: compact ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
            children: [
              if (compact)
                _ProgressSummary(course: course, total: total)
              else
                Expanded(
                  child: _ProgressSummary(course: course, total: total),
                ),
              if (action != null) ...[
                const SizedBox(width: AppSpace.x8, height: AppSpace.x4),
                action,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.course, required this.total});

  final Course course;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                l10n.progressPercent(
                  JalaliFormat.toPersianDigits('${(course.progress * 100).round()}'),
                ),
                style: theme.textTheme.labelMedium,
              ),
              const Spacer(),
              if (total > 0)
                Text(
                  l10n.completedOf(
                    JalaliFormat.toPersianDigits('${course.completedCount}'),
                    JalaliFormat.toPersianDigits('$total'),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.x2),
          AppProgressBar(value: course.progress),
        ],
      ),
    );
  }
}

/// A description clamped to a few lines, with a toggle only when it actually overflows.
class _Description extends StatefulWidget {
  const _Description({required this.text});

  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  static const _lines = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final style = theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _lines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: AppMotion.base,
                curve: AppMotion.curve,
                alignment: AlignmentDirectional.topStart,
                child: Text(
                  widget.text,
                  style: style,
                  maxLines: _expanded ? null : _lines,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                ),
              ),
              if (overflows || _expanded)
                Pressable(
                  onTap: () => setState(() => _expanded = !_expanded),
                  hoverColor: Colors.transparent,
                  pressedColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.x1),
                  builder: (context, state) => Text(
                    _expanded ? context.l10n.showLess : context.l10n.showMore,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: state.hovered ? colors.text : colors.accentText,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.video, required this.index, required this.allowDownload});

  final Video video;
  final int index;
  final bool allowDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final theme = Theme.of(context);
    final playable = video.isReady && !video.isLocked;

    final meta = <String>[
      if (video.isProcessing) l10n.processing else JalaliFormat.duration(video.duration),
      if (video.recordedAt != null) JalaliFormat.longDate(video.recordedAt!),
    ];

    return AppListRow(
      title: video.title,
      titleMaxLines: 2,
      enabled: playable,
      leading: _SessionMarker(video: video, index: index),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MetaLine(
            items: meta,
            style: theme.textTheme.bodySmall?.copyWith(
              color: playable ? colors.textSecondary : colors.textDisabled,
            ),
          ),
          // Only shown when part-watched: an empty bar under every unwatched session is noise.
          if (video.hasProgress) ...[
            const SizedBox(height: AppSpace.x2 - 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: AppProgressBar(value: video.progressFraction, height: 3),
            ),
          ],
          if (video.isLocked) ...[
            const SizedBox(height: AppSpace.x1),
            Row(
              children: [
                Icon(AppIcons.locked, size: 12, color: colors.warning),
                const SizedBox(width: AppSpace.x1 + 2),
                Expanded(
                  child: Text(
                    video.lockedReason!,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: video.downloaded
          ? Tooltip(
              message: l10n.downloaded,
              child: Icon(AppIcons.downloaded, size: 17, color: colors.success),
            )
          : allowDownload && video.isReady
          // M4: enqueue the .tihex download. Disabled rather than hidden so the capability is
          // visible and its arrival is not a surprise.
          ? AppIconButton(icon: AppIcons.download, tooltip: l10n.downloadSoon, onPressed: null)
          : null,
      onTap: playable ? () => context.push('/watch/${video.id}') : null,
    );
  }
}

/// Session number, or a state mark when the session is finished, in progress or not playable.
class _SessionMarker extends StatelessWidget {
  const _SessionMarker({required this.video, required this.index});

  final Video video;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final Widget child;
    BoxDecoration? decoration;

    if (video.completed) {
      decoration = BoxDecoration(color: colors.accentSubtle, shape: BoxShape.circle);
      child = Icon(AppIcons.completed, size: 14, color: colors.accentText);
    } else if (video.isProcessing) {
      child = const AppSpinner(size: 14);
    } else if (video.isLocked) {
      decoration = BoxDecoration(color: colors.surfaceRaised, shape: BoxShape.circle);
      child = Icon(AppIcons.locked, size: 13, color: colors.textTertiary);
    } else if (video.hasProgress) {
      child = AppProgressRing(value: video.progressFraction, size: 20);
    } else {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.border),
      );
      child = Text(
        JalaliFormat.toPersianDigits('$index'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1,
          color: colors.textSecondary,
        ),
      );
    }

    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: decoration,
      child: child,
    );
  }
}

class _CourseSkeleton extends StatelessWidget {
  const _CourseSkeleton({required this.back});

  final BackTarget back;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      back: back,
      maxWidth: 880,
      header: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 280, height: 24),
          SizedBox(height: AppSpace.x3),
          Skeleton(width: 120, height: 12),
          SizedBox(height: AppSpace.x5),
          Skeleton(height: 12),
          SizedBox(height: AppSpace.x2),
          Skeleton(width: 360, height: 12),
          SizedBox(height: AppSpace.x6),
          Skeleton(width: 240, height: 22),
          SizedBox(height: AppSpace.x6),
          Skeleton(width: 320, height: 4),
        ],
      ),
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: AppSpace.x10, bottom: AppSpace.x2),
            child: Skeleton(width: 140, height: 14),
          ),
        ),
        BleedSliver(
          sliver: SliverList.list(
            children: [
              for (var i = 0; i < 6; i++)
                SkeletonRow(leadingSize: 28, titleWidth: 180.0 + (i % 3) * 40),
            ],
          ),
        ),
      ],
    );
  }
}
