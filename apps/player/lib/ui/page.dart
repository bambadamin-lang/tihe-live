import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_icons.dart';
import '../core/theme/tokens.dart';
import '../l10n/l10n.dart';
import 'buttons.dart';

/// Where "back" goes when there is nothing to pop — a deep link, or a window restored on a
/// sub-page.
class BackTarget {
  const BackTarget({required this.label, required this.fallbackLocation});

  final String label;
  final String fallbackLocation;

  void go(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackLocation);
    }
  }
}

/// A scrolling page inside the app shell.
///
/// Content is centred at a readable [maxWidth] with a gutter that grows with the window. On a phone,
/// a sub-page gets a slim pinned bar with a back button; on larger windows, back is a quiet link
/// above the title, because there is room and a bar would only take height from the content.
class AppPage extends StatelessWidget {
  const AppPage({
    required this.slivers,
    this.header,
    this.back,
    this.maxWidth = 960,
    this.onRefresh,
    this.topPadding,
    super.key,
  });

  final Widget? header;
  final List<Widget> slivers;
  final BackTarget? back;
  final double maxWidth;
  final Future<void> Function()? onRefresh;
  final double? topPadding;

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = max(context.pageGutter, (constraints.maxWidth - maxWidth) / 2);
        final top = topPadding ?? (size.isCompact ? AppSpace.x3 : AppSpace.x10);

        Widget scroll = CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (back != null && size.isCompact)
              SliverAppBar(
                pinned: true,
                automaticallyImplyLeading: false,
                toolbarHeight: 52,
                backgroundColor: colors.background,
                titleSpacing: AppSpace.x2,
                title: AppIconButton(
                  icon: AppIcons.back,
                  tooltip: context.l10n.back,
                  onPressed: () => back!.go(context),
                ),
              )
            else
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).top)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                back != null && size.isCompact ? 0 : top,
                gutter,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (back != null && !size.isCompact) ...[
                      _BackLink(target: back!),
                      const SizedBox(height: AppSpace.x4),
                    ],
                    if (header != null) header!,
                  ],
                ),
              ),
            ),
            for (final sliver in slivers)
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: sliver is BleedSliver ? gutter - BleedSliver.bleed : gutter,
                ),
                sliver: sliver is BleedSliver ? sliver.sliver : sliver,
              ),
            SliverToBoxAdapter(
              child: SizedBox(height: AppSpace.x16 + MediaQuery.paddingOf(context).bottom),
            ),
          ],
        );

        if (onRefresh != null) {
          scroll = RefreshIndicator(onRefresh: onRefresh!, child: scroll);
        }
        return scroll;
      },
    );
  }
}

/// Marks a sliver of rows whose hover background should extend past the content edge, so the row
/// text stays aligned with the headings above it while the highlight has room to breathe.
class BleedSliver extends StatelessWidget {
  const BleedSliver({required this.sliver, super.key});

  /// Matches [AppListRow]'s horizontal padding.
  static const bleed = AppSpace.x3;

  final Widget sliver;

  @override
  Widget build(BuildContext context) => sliver;
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.target});

  final BackTarget target;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      // Aligns the icon, not the button's padding, with the title below.
      offset: Offset(Directionality.of(context) == TextDirection.rtl ? 10 : -10, 0),
      child: AppButton.ghost(
        label: target.label,
        icon: AppIcons.back,
        size: AppButtonSize.small,
        onPressed: () => target.go(context),
      ),
    );
  }
}

/// A page's title block.
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    super.key,
  });

  final String title;

  /// A string, or a widget (a meta line).
  final Object? subtitle;
  final List<Widget> actions;

  /// Anything that belongs to the header: badges, a progress summary, the main action.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final compact = context.windowSize.isCompact;

    final titleStyle = compact ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: titleStyle)),
              for (final action in actions) ...[const SizedBox(width: AppSpace.x2), action],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpace.x1),
            if (subtitle is String)
              Text(
                subtitle! as String,
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              )
            else
              subtitle! as Widget,
          ],
          if (bottom != null) ...[const SizedBox(height: AppSpace.x5), bottom!],
        ],
      ),
    );
  }
}

/// A section title with optional trailing metadata or action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.meta,
    this.action,
    this.padding = const EdgeInsets.only(top: AppSpace.x8, bottom: AppSpace.x2),
    super.key,
  });

  final String title;
  final String? meta;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (meta != null) ...[
            const SizedBox(width: AppSpace.x2),
            Text(meta!, style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary)),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}
