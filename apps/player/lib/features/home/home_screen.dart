import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tihe_classroom/tihe_classroom.dart' as live;

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import '../live/live_class_tile.dart';
import '../live/live_screen.dart' show courseTitles;

/// The dashboard after sign-in: the two halves of the app — live classes and the video library —
/// as two large cards, each saying what is waiting there right now.
///
/// A class that is live is also shown here with its join button, so on most days the student's
/// whole journey is: open the app, tap "join".
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthSignedIn ? auth.session.user : null;
    final name = user?.displayName?.trim();
    final classes = ref.watch(liveClassesProvider).value ?? const <live.LiveClass>[];
    final liveNow = classes.where((c) => c.isLive).take(3).toList();
    final titles = courseTitles(ref);

    Future<void> refresh() async {
      ref
        ..invalidate(liveClassesProvider)
        ..invalidate(coursesProvider);
    }

    return AppPage(
      maxWidth: 960,
      onRefresh: refresh,
      header: PageHeader(
        title: name == null || name.isEmpty ? l10n.greetingNoName : l10n.greeting(name),
        subtitle: l10n.dashboardSubtitle,
      ),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.x6)),
        const SliverToBoxAdapter(child: _Destinations()),
        if (liveNow.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader(title: l10n.liveNowSection)),
          SliverList.separated(
            itemCount: liveNow.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.x3),
            itemBuilder: (_, i) =>
                LiveNowCard(liveClass: liveNow[i], courseTitle: titles[liveNow[i].courseId]),
          ),
        ],
        if (user?.isAdmin ?? false) ...[
          SliverToBoxAdapter(child: SectionHeader(title: l10n.quickActions)),
          SliverToBoxAdapter(
            child: _DestinationCard(
              icon: AppIcons.admin,
              title: l10n.adminCardTitle,
              body: l10n.adminCardBody,
              onTap: () => context.go('/admin'),
              compact: true,
            ),
          ),
        ],
      ],
    );
  }
}

/// The two halves of the app, side by side where there is room.
class _Destinations extends ConsumerWidget {
  const _Destinations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.colors;
    final classes = ref.watch(liveClassesProvider);
    final courses = ref.watch(coursesProvider);

    final liveCard = _DestinationCard(
      icon: AppIcons.live,
      tint: colors.danger,
      title: l10n.liveCardTitle,
      body: l10n.liveCardBody,
      status: classes.whenOrNull(data: (items) => _liveStatus(context, items)),
      onTap: () => context.go('/live'),
    );

    final libraryCard = _DestinationCard(
      icon: AppIcons.library,
      title: l10n.libraryCardTitle,
      body: l10n.libraryCardBody,
      status: courses.whenOrNull(data: (items) => _libraryStatus(context, items)),
      onTap: () => context.go('/library'),
    );

    if (context.windowSize.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          liveCard,
          const SizedBox(height: AppSpace.x3),
          libraryCard,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: liveCard),
          const SizedBox(width: AppSpace.x4),
          Expanded(child: libraryCard),
        ],
      ),
    );
  }

  static Widget _liveStatus(BuildContext context, List<live.LiveClass> classes) {
    final l10n = context.l10n;
    final colors = context.colors;
    final now = classes.where((c) => c.isLive).length;
    if (now > 0) {
      return _Status(
        leading: live.PulsingDot(color: colors.danger),
        text: l10n.liveNowCount(JalaliFormat.toPersianDigits('$now')),
        color: colors.danger,
      );
    }
    final soon = DateTime.now().toUtc();
    final next = classes
        .map((c) => c.scheduledStartAt)
        .whereType<DateTime>()
        .where((at) => at.isAfter(soon))
        .fold<DateTime?>(null, (best, at) => best == null || at.isBefore(best) ? at : best);
    return _Status(
      text: next == null ? l10n.noLiveNow : l10n.nextClassAt(JalaliFormat.schedule(next)),
    );
  }

  static Widget _libraryStatus(BuildContext context, List<Course> courses) {
    final l10n = context.l10n;
    if (courses.isEmpty) return _Status(text: l10n.libraryCardEmpty);
    final inProgress = courses.where((c) => c.progress > 0 && c.progress < 1).firstOrNull;
    return _Status(
      text: inProgress != null
          ? l10n.continueWatching(inProgress.title)
          : l10n.courseCount(JalaliFormat.toPersianDigits('${courses.length}')),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.text, this.leading, this.color});

  final String text;
  final Widget? leading;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: AppSpace.x2)],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color ?? colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// A large, glass, clickable card: an icon, what is there, and what is waiting.
class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.status,
    this.tint,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final Widget? status;
  final Color? tint;

  /// A one-row card, for secondary destinations.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final accent = tint ?? colors.accent;

    final badge = Container(
      width: compact ? 40 : 52,
      height: compact ? 40 : 52,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
      ),
      child: Icon(icon, size: compact ? 20 : 26, color: accent),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: compact ? theme.textTheme.titleSmall : theme.textTheme.titleLarge),
        const SizedBox(height: AppSpace.x1),
        Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
      ],
    );

    return live.Glass(
      radius: compact ? 18 : 24,
      child: Pressable(
        onTap: onTap,
        semanticLabel: title,
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
        padding: EdgeInsets.all(compact ? AppSpace.x4 : AppSpace.x6),
        child: compact
            ? Row(
                children: [
                  badge,
                  const SizedBox(width: AppSpace.x4),
                  Expanded(child: text),
                  Icon(AppIcons.forward, size: 18, color: colors.textTertiary),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      badge,
                      const Spacer(),
                      Icon(AppIcons.forward, size: 20, color: colors.textTertiary),
                    ],
                  ),
                  const SizedBox(height: AppSpace.x5),
                  text,
                  if (status != null) ...[const SizedBox(height: AppSpace.x5), status!],
                ],
              ),
      ),
    );
  }
}
