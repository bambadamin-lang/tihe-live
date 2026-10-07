import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tihe_classroom/tihe_classroom.dart' as live;

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import 'live_class_tile.dart';

/// Course titles by id, for labelling classes. Empty until the library has loaded, or if it fails:
/// a class is still joinable without its course's name.
Map<String, String> courseTitles(WidgetRef ref) => {
  for (final course in ref.watch(coursesProvider).value ?? const <Course>[])
    course.id: course.title,
};

/// The classes of every course the student attends (or teaches): live ones first, then by time.
///
/// Refreshes itself while open, so a student waiting for class sees the join button appear when
/// the teacher starts, without knowing to pull down.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  /// How often the list is fetched again while it is on screen.
  static const refreshEvery = Duration(seconds: 20);

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(LiveScreen.refreshEvery, (_) => ref.invalidate(liveClassesProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final classes = ref.watch(liveClassesProvider);
    final titles = courseTitles(ref);

    return AppPage(
      maxWidth: 820,
      onRefresh: () async => ref.invalidate(liveClassesProvider),
      header: PageHeader(title: l10n.liveTitle, subtitle: l10n.liveSubtitle),
      slivers: [
        ...classes.when(
          skipLoadingOnRefresh: true,
          loading: () => [
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.x6)),
            SliverToBoxAdapter(
              child: AppListGroup(
                children: [for (var i = 0; i < 3; i++) const SkeletonRow(titleWidth: 180)],
              ),
            ),
          ],
          error: (error, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorView(error: error, onRetry: () => ref.invalidate(liveClassesProvider)),
            ),
          ],
          data: (items) => items.isEmpty
              ? [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: AppIcons.live,
                      title: l10n.liveEmpty,
                      hint: l10n.liveEmptyHint,
                    ),
                  ),
                ]
              : _sections(context, items, titles),
        ),
      ],
    );
  }

  List<Widget> _sections(
    BuildContext context,
    List<live.LiveClass> items,
    Map<String, String> titles,
  ) {
    final l10n = context.l10n;
    final colors = context.colors;
    final now = items.where((c) => c.isLive).toList();
    final upcoming = items.where((c) => !c.isLive && c.scheduledStartAt != null).toList();
    final unscheduled = items.where((c) => !c.isLive && c.scheduledStartAt == null).toList();
    // Only someone who cannot start a class is waiting for one to start.
    final waiting = now.isEmpty && items.any((c) => !canHost(ref, c));

    List<Widget> rows(String title, List<live.LiveClass> classes) => [
      SliverToBoxAdapter(child: SectionHeader(title: title)),
      SliverToBoxAdapter(
        child: AppListGroup(
          children: [
            for (final c in classes) ClassRow(liveClass: c, courseTitle: titles[c.courseId]),
          ],
        ),
      ),
    ];

    return [
      if (now.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(title: l10n.liveNowSection)),
        SliverList.separated(
          itemCount: now.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.x3),
          itemBuilder: (_, i) =>
              LiveNowCard(liveClass: now[i], courseTitle: titles[now[i].courseId]),
        ),
      ],
      if (upcoming.isNotEmpty) ...rows(l10n.upcomingSection, upcoming),
      if (unscheduled.isNotEmpty) ...rows(l10n.otherClassesSection, unscheduled),
      if (waiting)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.x5),
            child: Row(
              children: [
                Icon(AppIcons.info, size: 16, color: colors.textTertiary),
                const SizedBox(width: AppSpace.x2),
                Expanded(
                  child: Text(
                    l10n.classWaitHint,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}
