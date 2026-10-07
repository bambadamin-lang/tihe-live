import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import '../shell/app_shell.dart' show roleLabelOf;
import 'add_user_dialog.dart';
import 'limit_stepper.dart';

/// Administration: how many devices an account may be signed in on at once, and the accounts.
///
/// The limit comes first because it is the setting the institute asked for by name; the users
/// below are found by typing, never by scrolling a list of phone numbers.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addUser() async {
    final created = await showAddUserDialog(context);
    if (created == null || !mounted) return;
    ref.invalidate(adminUsersProvider);
    await context.push('/admin/users/$created');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final users = ref.watch(adminUsersProvider(_query));

    return AppPage(
      maxWidth: 820,
      onRefresh: () async {
        ref
          ..invalidate(instituteSettingsProvider)
          ..invalidate(adminUsersProvider);
      },
      header: PageHeader(
        title: l10n.adminTitle,
        subtitle: l10n.adminSubtitle,
        actions: [
          AppButton.primary(label: l10n.addUser, icon: AppIcons.addUser, onPressed: _addUser),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(child: SectionHeader(title: l10n.defaultDeviceLimit)),
        const SliverToBoxAdapter(child: _DefaultLimitCard()),
        SliverToBoxAdapter(child: SectionHeader(title: l10n.usersTitle)),
        SliverToBoxAdapter(
          child: AppTextField(
            controller: _search,
            hint: l10n.usersSearchHint,
            prefixIcon: AppIcons.search,
            onChanged: (text) => setState(() => _query = text.trim()),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.x3)),
        ...users.when(
          skipLoadingOnRefresh: true,
          loading: () => [
            SliverToBoxAdapter(
              child: AppListGroup(
                children: [for (var i = 0; i < 4; i++) const SkeletonRow(titleWidth: 160)],
              ),
            ),
          ],
          error: (error, _) => [
            SliverToBoxAdapter(
              child: ErrorView(error: error, onRetry: () => ref.invalidate(adminUsersProvider)),
            ),
          ],
          data: (items) => [
            if (items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.x8),
                  child: EmptyState(icon: AppIcons.users, title: l10n.usersEmpty),
                ),
              )
            else
              SliverToBoxAdapter(
                child: AppListGroup(children: [for (final u in items) _UserRow(user: u)]),
              ),
          ],
        ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = user.user.displayName?.trim();
    final title = name == null || name.isEmpty ? user.user.phoneMasked : name;

    return AppListRow(
      title: title,
      leading: Monogram(text: title, size: 36, circle: true),
      subtitle: MetaLine(
        items: [
          user.user.phoneMasked,
          roleLabelOf(user.user.role, l10n),
          l10n.signedInOf(
            JalaliFormat.toPersianDigits('${user.signedInDevices}'),
            JalaliFormat.toPersianDigits('${user.effectiveMaxDevices}'),
          ),
        ],
        maxLines: 2,
      ),
      trailing: user.user.status == 'suspended'
          ? AppBadge(label: l10n.statusSuspended, tone: BadgeTone.danger)
          : user.user.mustChangePassword
          ? AppBadge(label: l10n.awaitingNewPassword, tone: BadgeTone.warning)
          : null,
      showChevron: true,
      onTap: () => context.push('/admin/users/${user.user.id}'),
    );
  }
}

/// The institute's default device limit, for every account without its own.
class _DefaultLimitCard extends ConsumerStatefulWidget {
  const _DefaultLimitCard();

  @override
  ConsumerState<_DefaultLimitCard> createState() => _DefaultLimitCardState();
}

class _DefaultLimitCardState extends ConsumerState<_DefaultLimitCard> {
  /// The value being edited; null while it matches the server.
  int? _draft;
  bool _saving = false;

  Future<void> _save(int value) async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      await ref.read(adminRepositoryProvider).setDefaultMaxDevices(value);
      ref
        ..invalidate(instituteSettingsProvider)
        // Accounts on the default now show the new limit.
        ..invalidate(adminUsersProvider);
      if (!mounted) return;
      setState(() => _draft = null);
      showToast(context, l10n.saved, tone: ToastTone.success);
    } on ApiError catch (e) {
      if (mounted) showToast(context, e.messageFa, tone: ToastTone.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;
    final settings = ref.watch(instituteSettingsProvider);
    final saved = settings.value?.defaultMaxDevices;
    final value = _draft ?? saved;
    final compact = context.windowSize.isCompact;

    final hint = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.defaultDeviceLimitHint,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpace.x1),
        Text(
          l10n.limitLoweredHint,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value == null)
          const AppSpinner()
        else
          LimitStepper(
            value: value,
            onChanged: _saving ? null : (v) => setState(() => _draft = v == saved ? null : v),
          ),
        if (_draft != null) ...[
          const SizedBox(width: AppSpace.x3),
          AppButton.primary(label: l10n.save, loading: _saving, onPressed: () => _save(_draft!)),
        ],
      ],
    );

    if (settings.hasError && saved == null) {
      return ErrorView(
        error: settings.error!,
        onRetry: () => ref.invalidate(instituteSettingsProvider),
      );
    }

    return AppSurface(
      padding: const EdgeInsets.all(AppSpace.x4),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                hint,
                const SizedBox(height: AppSpace.x4),
                controls,
              ],
            )
          : Row(
              children: [
                Expanded(child: hint),
                const SizedBox(width: AppSpace.x5),
                controls,
              ],
            ),
    );
  }
}
