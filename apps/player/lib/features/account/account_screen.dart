import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/preferences.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart';

/// The student's profile and preferences.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.signOut,
      message: l10n.signOutConfirm,
      confirmLabel: l10n.signOut,
      destructive: true,
    );
    if (confirmed) await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthSignedIn ? auth.session.user : null;
    final themeMode = ref.watch(themeModeProvider);
    final version = ref.watch(appVersionProvider).value;
    final compact = context.windowSize.isCompact;
    final touch = isTouchPlatform(context);

    final appearance = AppSegmented<ThemeMode>(
      value: themeMode,
      expand: compact,
      onChanged: (mode) => ref.read(themeModeProvider.notifier).set(mode),
      segments: [
        AppSegment(value: ThemeMode.system, label: l10n.themeSystem, icon: AppIcons.themeSystem),
        AppSegment(value: ThemeMode.light, label: l10n.themeLight, icon: AppIcons.themeLight),
        AppSegment(value: ThemeMode.dark, label: l10n.themeDark, icon: AppIcons.themeDark),
      ],
    );

    return AppPage(
      maxWidth: 720,
      header: PageHeader(title: l10n.accountTitle),
      slivers: [
        if (user != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.x6),
              child: Row(
                children: [
                  Monogram(text: displayNameOf(user, l10n), size: 52, circle: true),
                  const SizedBox(width: AppSpace.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayNameOf(user, l10n),
                                style: theme.textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (user.displayName != null) ...[
                              const SizedBox(width: AppSpace.x2),
                              AppBadge(label: roleLabelOf(user.role, l10n)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Already masked by the server; LTR so the digits read in order.
                        Text(
                          user.phoneMasked,
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        SliverToBoxAdapter(child: SectionHeader(title: l10n.preferences)),
        SliverToBoxAdapter(
          child: AppListGroup(
            children: [
              if (compact)
                Padding(
                  padding: const EdgeInsets.all(AppSpace.x3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _GroupLabel(title: l10n.appearance, hint: l10n.appearanceHint),
                      const SizedBox(height: AppSpace.x3),
                      appearance,
                    ],
                  ),
                )
              else
                AppListRow(
                  title: l10n.appearance,
                  subtitle: l10n.appearanceHint,
                  leading: const IconTile(icon: AppIcons.appearance),
                  trailing: appearance,
                ),
              AppListRow(
                title: l10n.changePassword,
                leading: const IconTile(icon: AppIcons.code),
                showChevron: true,
                onTap: () => context.push('/account/password'),
              ),
              if (user?.isAdmin ?? false)
                AppListRow(
                  title: l10n.adminTitle,
                  subtitle: l10n.openAdmin,
                  leading: const IconTile(icon: AppIcons.admin),
                  showChevron: true,
                  onTap: () => context.go('/admin'),
                ),
              AppListRow(
                title: l10n.devicesTitle,
                subtitle: l10n.manageDevices,
                leading: const IconTile(icon: AppIcons.devices),
                showChevron: true,
                onTap: () => context.push('/devices'),
              ),
              if (!touch)
                AppListRow(
                  title: l10n.shortcuts,
                  subtitle: l10n.shortcutsHint,
                  leading: const IconTile(icon: AppIcons.shortcuts),
                  showChevron: true,
                  onTap: () => showShortcutsDialog(context),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(child: SectionHeader(title: l10n.about)),
        SliverToBoxAdapter(
          child: AppListGroup(
            children: [
              AppListRow(
                title: l10n.appTitle,
                subtitle: version == null
                    ? null
                    : l10n.version(JalaliFormat.toPersianDigits(version)),
                leading: const BrandMark(size: 36),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.x8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: l10n.signOut,
                icon: AppIcons.signOut,
                variant: AppButtonVariant.dangerGhost,
                expand: compact,
                onPressed: () => _signOut(context, ref),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(hint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// The keyboard shortcuts, as a reference dialog.
Future<void> showShortcutsDialog(BuildContext context) {
  final l10n = context.l10n;
  final isMac = Theme.of(context).platform == TargetPlatform.macOS;

  final rows = <(String, List<String>)>[
    (l10n.shortcutPlayPause, ['Space', 'K']),
    (l10n.shortcutSeek, ['←', '→']),
    (l10n.shortcutVolume, ['↑', '↓']),
    (l10n.shortcutMute, ['M']),
    (l10n.shortcutFullscreen, ['F']),
    (l10n.shortcutNextPrev, ['Shift N', 'Shift P']),
    (l10n.shortcutSearch, [if (isMac) '⌘K' else 'Ctrl K']),
  ];

  return showDialog<void>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) => AppDialog(
      title: l10n.shortcuts,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, keys) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.x2 - 2),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  for (var i = 0; i < keys.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpace.x1),
                    KeyCap(keys[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
