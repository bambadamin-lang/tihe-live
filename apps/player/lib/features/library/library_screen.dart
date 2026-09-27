import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/theme/jalali.dart';
import '../../l10n/l10n.dart';
import '../shared/error_view.dart';

/// The student's course library, and search across it.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final searching = _query.trim().length >= 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.devices_outlined),
            tooltip: l10n.devicesTitle,
            onPressed: () => context.push('/devices'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: searching ? _searchResults(l10n) : _courseList(l10n),
          ),
        ],
      ),
    );
  }

  Widget _courseList(AppLocalizations l10n) {
    final courses = ref.watch(coursesProvider);

    return courses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(coursesProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _EmptyState(
            icon: Icons.menu_book_outlined,
            title: l10n.libraryEmpty,
            hint: l10n.libraryEmptyHint,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(coursesProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, index) => _CourseCard(course: items[index]),
          ),
        );
      },
    );
  }

  Widget _searchResults(AppLocalizations l10n) {
    final results = ref.watch(searchProvider(_query));

    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error),
      data: (hits) {
        if (hits.isEmpty) {
          return _EmptyState(icon: Icons.search_off, title: l10n.searchEmpty);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: hits.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final hit = hits[index];
            if (hit.kind == 'course' && hit.course != null) {
              return _CourseCard(course: hit.course!);
            }
            if (hit.video != null) {
              return _VideoTile(video: hit.video!, showCourseHint: true);
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Card(
      child: InkWell(
        onTap: () => context.push('/course/${course.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _ProgressRing(value: course.progress),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (course.teacherName != null) course.teacherName!,
                        l10n.videoCount(JalaliFormat.toPersianDigits('${course.videoCount}')),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!course.policy.allowDownload) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.downloadNotAllowed,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Chevron points left: in an RTL layout, forward is leftward.
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}

/// A course's watched fraction as a ring with the percentage inside.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 4,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          Text(
            JalaliFormat.toPersianDigits('${(value * 100).round()}'),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video, this.showCourseHint = false});

  final Video video;
  final bool showCourseHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
        video.downloaded ? Icons.download_done : Icons.play_circle_outline,
        color: video.isReady ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        video.isProcessing ? l10n.processing : JalaliFormat.duration(video.duration),
      ),
      enabled: video.isReady,
      onTap: video.isReady ? () => context.push('/watch/${video.id}') : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, this.hint});

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
