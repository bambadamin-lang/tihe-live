import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../core/update/updater.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';

/// Offers a new version on the dashboard. Never shown in class or the player — both cover the
/// shell — so an update cannot interrupt a lesson; the student chooses when to install.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updater = ref.watch(updaterProvider);
    if (updater == null) return const SizedBox.shrink();
    final l10n = context.l10n;

    return ValueListenableBuilder(
      valueListenable: updater,
      builder: (context, state, _) => switch (state) {
        UpdateIdle() => const SizedBox.shrink(),
        UpdateAvailable(:final release) => _Banner(
          title: l10n.updateReady(JalaliFormat.toPersianDigits('${release.version}')),
          hint: l10n.updateHint,
          actions: [
            AppButton.ghost(label: l10n.later, onPressed: updater.dismiss),
            AppButton.primary(label: l10n.updateNow, onPressed: updater.install),
          ],
        ),
        UpdateDownloading(:final release, :final progress) => _Banner(
          title: l10n.updateDownloading(
            JalaliFormat.toPersianDigits('${release.version}'),
            JalaliFormat.toPersianDigits('${(progress * 100).floor()}'),
          ),
          progress: progress,
        ),
        UpdateInstalling() => _Banner(
          title: l10n.updateInstalling,
          hint: l10n.updateInstallingHint,
          progress: 1,
        ),
        UpdateFailed(:final messageFa) => _Banner(
          title: l10n.updateFailed,
          hint: messageFa,
          danger: true,
          actions: [
            AppButton.ghost(label: l10n.later, onPressed: updater.dismiss),
            AppButton.primary(label: l10n.retry, onPressed: updater.install),
          ],
        ),
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.title,
    this.hint,
    this.progress,
    this.danger = false,
    this.actions = const [],
  });

  final String title;
  final String? hint;
  final double? progress;
  final bool danger;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final tint = danger ? colors.danger : colors.accent;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.x6),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.x4),
          decoration: BoxDecoration(
            color: danger ? colors.dangerSubtle : colors.accentSubtle,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: tint.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(danger ? AppIcons.error : AppIcons.download, size: 18, color: tint),
                  const SizedBox(width: AppSpace.x2),
                  Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                ],
              ),
              if (hint != null) ...[
                const SizedBox(height: AppSpace.x1),
                Text(
                  hint!,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: AppSpace.x3),
                AppProgressBar(value: progress!),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpace.x3),
                Wrap(alignment: WrapAlignment.end, spacing: AppSpace.x2, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
