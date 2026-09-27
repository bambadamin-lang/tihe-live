import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/theme/jalali.dart';
import '../../l10n/l10n.dart';
import '../shared/error_view.dart';

/// A course: its sections, its sessions, and what the student has watched.
class CourseScreen extends ConsumerWidget {
  const CourseScreen({required this.courseId, super.key});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseProvider(courseId));

    return Scaffold(
      body: course.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(
            error: error,
            onRetry: () => ref.invalidate(courseProvider(courseId)),
          ),
        ),
        data: (data) => _CourseBody(course: data),
      ),
    );
  }
}

class _CourseBody extends StatelessWidget {
  const _CourseBody({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: Text(course.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (course.teacherName != null)
                  Text(
                    course.teacherName!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (course.description != null) ...[
                  const SizedBox(height: 12),
                  Text(course.description!, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 16),
                _ProgressBar(
                  value: course.progress,
                  label: l10n.progressPercent(
                    JalaliFormat.toPersianDigits('${(course.progress * 100).round()}'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        for (final section in course.sections) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(section.title, style: theme.textTheme.titleMedium),
            ),
          ),
          SliverList.separated(
            itemCount: section.videos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) => _SessionTile(
              video: section.videos[index],
              index: index + 1,
              allowDownload: course.policy.allowDownload,
            ),
          ),
        ],
        if (course.looseVideos.isNotEmpty)
          SliverList.separated(
            itemCount: course.looseVideos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) => _SessionTile(
              video: course.looseVideos[index],
              index: index + 1,
              allowDownload: course.policy.allowDownload,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value, minHeight: 6),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.video,
    required this.index,
    required this.allowDownload,
  });

  final Video video;
  final int index;
  final bool allowDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final subtitle = <String>[
      if (video.isProcessing) l10n.processing else JalaliFormat.duration(video.duration),
      if (video.recordedAt != null) JalaliFormat.longDate(video.recordedAt!),
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      enabled: video.isReady && !video.isLocked,
      leading: _Leading(video: video, index: index),
      title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(subtitle, style: theme.textTheme.bodySmall),
          // Only shown when part-watched: a full-width empty bar under every unwatched session is
          // noise.
          if (video.hasProgress) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: video.progressFraction, minHeight: 3),
            ),
          ],
          if (video.isLocked) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 13),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(video.lockedReason!, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: video.downloaded
          ? Tooltip(
              message: l10n.downloaded,
              child: Icon(Icons.download_done, color: theme.colorScheme.primary),
            )
          : allowDownload && video.isReady
              ? IconButton(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: l10n.download,
                  // M4: enqueue the .tihex download. Disabled rather than hidden so the capability
                  // is visible and its arrival is not a surprise.
                  onPressed: null,
                )
              : null,
      onTap: video.isReady && !video.isLocked ? () => context.push('/watch/${video.id}') : null,
    );
  }
}

/// Session number, or a state icon when the session is not playable.
class _Leading extends StatelessWidget {
  const _Leading({required this.video, required this.index});

  final Video video;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (video.completed) {
      return CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(Icons.check, size: 18, color: theme.colorScheme.onPrimaryContainer),
      );
    }
    if (video.isProcessing) {
      return const CircleAvatar(
        child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return CircleAvatar(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        JalaliFormat.toPersianDigits('$index'),
        style: theme.textTheme.labelLarge,
      ),
    );
  }
}
