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
import 'course_row.dart';

/// The student's home: what they were in the middle of, then every course they are enrolled in.
///
/// Search lives in its own destination (sidebar, rail or bottom bar, and Ctrl+K), so this page can
/// be about the library alone.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final courses = ref.watch(coursesProvider);
    Future<void> refresh() async => ref.invalidate(coursesProvider);

    return courses.when(
      skipLoadingOnRefresh: true,
      loading: () => const _LibrarySkeleton(),
      error: (error, _) => AppPage(
        header: PageHeader(title: l10n.libraryTitle),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorView(error: error, onRetry: () => ref.invalidate(coursesProvider)),
          ),
        ],
      ),
      data: (items) {
        if (items.isEmpty) {
          return AppPage(
            onRefresh: refresh,
            header: PageHeader(title: l10n.libraryTitle),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: AppIcons.course,
                  title: l10n.libraryEmpty,
                  hint: l10n.libraryEmptyHint,
                ),
              ),
            ],
          );
        }

        final inProgress = items.where((c) => c.progress > 0 && c.progress < 1).take(3).toList();
        final sessions = items.fold<int>(0, (sum, c) => sum + c.videoCount);

        return AppPage(
          onRefresh: refresh,
          header: PageHeader(
            title: l10n.libraryTitle,
            subtitle: l10n.librarySummary(
              JalaliFormat.toPersianDigits('${items.length}'),
              JalaliFormat.toPersianDigits('$sessions'),
            ),
          ),
          slivers: [
            if (inProgress.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: l10n.continueLearning,
                  padding: const EdgeInsets.only(top: AppSpace.x6, bottom: AppSpace.x3),
                ),
              ),
              SliverToBoxAdapter(child: _ContinueStrip(courses: inProgress)),
            ],
            SliverToBoxAdapter(
              child: SectionHeader(
                title: l10n.allCourses,
                meta: JalaliFormat.toPersianDigits('${items.length}'),
                padding: EdgeInsets.only(
                  top: inProgress.isEmpty ? AppSpace.x6 : AppSpace.x10,
                  bottom: AppSpace.x2,
                ),
              ),
            ),
            BleedSliver(
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (_, index) => CourseRow(course: items[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Courses in progress, as the one place in the library that earns a card: they are the next
/// thing to do.
class _ContinueStrip extends StatelessWidget {
  const _ContinueStrip({required this.courses});

  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;

    if (size.isCompact) {
      // A horizontal strip on a phone, with the next card peeking in to show there is more.
      return SizedBox(
        height: _ContinueCard.height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: courses.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpace.x3),
          itemBuilder: (context, index) => SizedBox(
            width: courses.length == 1
                ? MediaQuery.sizeOf(context).width - context.pageGutter * 2
                : MediaQuery.sizeOf(context).width * 0.78,
            child: _ContinueCard(course: courses[index]),
          ),
        ),
      );
    }

    final columns = size.isExpanded ? 3 : 2;
    final visible = courses.take(columns).toList();
    return Row(
      children: [
        for (var i = 0; i < columns; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.x3),
          Expanded(
            child: i < visible.length ? _ContinueCard(course: visible[i]) : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.course});

  // Fits a two-line title; the strip needs a fixed height to scroll horizontally.
  static const height = 150.0;

  final Course course;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final percent = JalaliFormat.toPersianDigits('${(course.progress * 100).round()}');

    return Pressable(
      onTap: () => context.push('/course/${course.id}'),
      semanticLabel: course.title,
      color: colors.surface,
      hoverColor: colors.surfaceRaised,
      pressedColor: colors.surfaceHover,
      borderRadius: AppRadius.lgAll,
      border: Border.all(color: colors.border),
      builder: (context, state) => SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.title,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              MetaLine(
                items: [
                  if (course.teacherName != null) course.teacherName!,
                  l10n.videoCount(JalaliFormat.toPersianDigits('${course.videoCount}')),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(child: AppProgressBar(value: course.progress)),
                  const SizedBox(width: AppSpace.x3),
                  Text('$percent٪', style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: AppSpace.x3),
              Row(
                children: [
                  Text(
                    l10n.continueAction,
                    style: theme.textTheme.labelMedium?.copyWith(color: colors.accentText),
                  ),
                  const SizedBox(width: AppSpace.x1),
                  AnimatedSlide(
                    duration: AppMotion.fast,
                    offset:
                        Offset(state.hovered ? -0.15 : 0, 0) *
                        (Directionality.of(context) == TextDirection.rtl ? 1 : -1),
                    child: Icon(AppIcons.forward, size: 14, color: colors.accentText),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) {
    final compact = context.windowSize.isCompact;
    return AppPage(
      header: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 160, height: 22),
          SizedBox(height: AppSpace.x3),
          Skeleton(width: 120, height: 12),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.x10, bottom: AppSpace.x3),
            child: Row(
              children: [
                for (var i = 0; i < (compact ? 1 : 3); i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.x3),
                  const Expanded(
                    child: Skeleton(height: _ContinueCard.height, radius: AppRadius.lg),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: AppSpace.x8, bottom: AppSpace.x2),
            child: Skeleton(width: 96, height: 14),
          ),
        ),
        BleedSliver(
          sliver: SliverList.list(
            children: [
              for (var i = 0; i < 6; i++)
                SkeletonRow(leadingSize: 40, titleWidth: 160.0 + (i % 3) * 40),
            ],
          ),
        ),
      ],
    );
  }
}
