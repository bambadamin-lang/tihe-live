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
import '../library/course_row.dart';

/// Search across the student's courses and sessions.
///
/// Debouncing and the two-character minimum live in [searchProvider], so this screen only renders.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  /// The last results shown, kept on screen while the next query loads, so typing refines the
  /// list instead of flashing a skeleton on every keystroke.
  List<SearchHit>? _lastHits;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _query = '';
      _lastHits = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final searching = _query.trim().length >= 2;

    return AppPage(
      maxWidth: 760,
      header: PageHeader(
        title: l10n.searchTitle,
        bottom: AppTextField(
          controller: _controller,
          autofocus: true,
          hint: l10n.searchHint,
          prefixIcon: AppIcons.search,
          size: AppTextFieldSize.large,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() {
            _query = value;
            if (value.trim().length < 2) _lastHits = null;
          }),
          suffix: _query.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpace.x1),
                  child: AppIconButton(
                    icon: AppIcons.close,
                    tooltip: l10n.close,
                    size: AppButtonSize.small,
                    color: colors.textTertiary,
                    onPressed: _clear,
                  ),
                ),
        ),
      ),
      slivers: searching
          ? _results(l10n)
          : [
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: AppIcons.search,
                  title: l10n.searchPrompt,
                  hint: l10n.searchPromptHint,
                ),
              ),
            ],
    );
  }

  List<Widget> _results(AppLocalizations l10n) {
    final results = ref.watch(searchProvider(_query));

    if (results.hasError && !results.isLoading) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: ErrorView(error: results.error!)),
      ];
    }
    if (results.hasValue) _lastHits = results.value;
    final hits = results.valueOrNull ?? _lastHits;

    if (hits == null) {
      return [
        SliverPadding(
          padding: const EdgeInsets.only(top: AppSpace.x6),
          sliver: BleedSliver(
            sliver: SliverList.list(
              children: [
                for (var i = 0; i < 5; i++) SkeletonRow(titleWidth: 140.0 + (i % 3) * 50),
              ],
            ),
          ),
        ),
      ];
    }

    if (hits.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: AppIcons.noResults,
            title: l10n.searchEmpty,
            hint: l10n.searchEmptyHint,
          ),
        ),
      ];
    }

    final courses = [
      for (final hit in hits)
        if (hit.kind == 'course' && hit.course != null) hit.course!,
    ];
    final videos = [
      for (final hit in hits)
        if (hit.kind != 'course' && hit.video != null) hit.video!,
    ];

    return [
      if (courses.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.searchCourses,
            meta: JalaliFormat.toPersianDigits('${courses.length}'),
            padding: const EdgeInsets.only(top: AppSpace.x6, bottom: AppSpace.x2),
          ),
        ),
        BleedSliver(
          sliver: SliverList.builder(
            itemCount: courses.length,
            itemBuilder: (_, i) => CourseRow(course: courses[i]),
          ),
        ),
      ],
      if (videos.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.searchSessions,
            meta: JalaliFormat.toPersianDigits('${videos.length}'),
            padding: EdgeInsets.only(
              top: courses.isEmpty ? AppSpace.x6 : AppSpace.x8,
              bottom: AppSpace.x2,
            ),
          ),
        ),
        BleedSliver(
          sliver: SliverList.builder(
            itemCount: videos.length,
            itemBuilder: (_, i) => _VideoResult(video: videos[i]),
          ),
        ),
      ],
    ];
  }
}

class _VideoResult extends StatelessWidget {
  const _VideoResult({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;

    return AppListRow(
      title: video.title,
      titleMaxLines: 2,
      enabled: video.isReady,
      leading: IconTile(
        icon: video.downloaded ? AppIcons.downloaded : AppIcons.session,
        iconColor: video.isReady ? colors.accentText : null,
      ),
      subtitle: video.isProcessing ? l10n.processing : JalaliFormat.duration(video.duration),
      trailing: video.hasProgress
          ? SizedBox(width: 64, child: AppProgressBar(value: video.progressFraction))
          : null,
      onTap: () => context.push('/watch/${video.id}'),
    );
  }
}
