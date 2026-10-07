import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/api/repositories.dart' show AdminRepository;
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import '../devices/device_icon.dart';
import '../shell/app_shell.dart' show roleLabelOf;
import 'add_user_dialog.dart' show generateTemporaryPassword, passwordProblem;
import 'limit_stepper.dart';

/// One account, for an admin: its device limit, where it is signed in, its courses, and the
/// account itself (name, role, password, suspension).
///
/// Every change saves at once and the page reloads from the server's answer, so what is shown is
/// always what is stored.
class AdminUserScreen extends ConsumerWidget {
  const AdminUserScreen({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final detail = ref.watch(adminUserProvider(userId));
    final back = BackTarget(label: l10n.adminTitle, fallbackLocation: '/admin');

    return detail.when(
      skipLoadingOnRefresh: true,
      loading: () => AppPage(
        back: back,
        maxWidth: 820,
        slivers: [
          SliverToBoxAdapter(
            child: AppListGroup(
              children: [for (var i = 0; i < 4; i++) const SkeletonRow(titleWidth: 180)],
            ),
          ),
        ],
      ),
      error: (error, _) => AppPage(
        back: back,
        maxWidth: 820,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorView(
              error: error,
              onRetry: () => ref.invalidate(adminUserProvider(userId)),
            ),
          ),
        ],
      ),
      data: (d) => _AdminUserPage(detail: d, back: back),
    );
  }
}

class _AdminUserPage extends ConsumerStatefulWidget {
  const _AdminUserPage({required this.detail, required this.back});

  final AdminUserDetail detail;
  final BackTarget back;

  @override
  ConsumerState<_AdminUserPage> createState() => _AdminUserPageState();
}

class _AdminUserPageState extends ConsumerState<_AdminUserPage> {
  /// Which action is in flight, so only its own button spins.
  String? _busy;

  AdminUser get _summary => widget.detail.summary;
  AppUser get _user => _summary.user;

  /// Runs an admin change, then reloads this account and the list it came from.
  Future<bool> _run(String key, Future<void> Function() action, {String? done}) async {
    setState(() => _busy = key);
    try {
      await action();
      ref
        ..invalidate(adminUserProvider(_user.id))
        ..invalidate(adminUsersProvider);
      if (mounted && done != null) showToast(context, done, tone: ToastTone.success);
      return true;
    } on ApiError catch (e) {
      if (mounted) showToast(context, e.messageFa, tone: ToastTone.danger);
      return false;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  AdminRepository get _admin => ref.read(adminRepositoryProvider);

  Future<void> _signOutDevice(Device device) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.signOutDevice,
      message: l10n.signOutDeviceConfirm,
      confirmLabel: l10n.signOutDevice,
      destructive: true,
    );
    if (!confirmed) return;
    await _run(
      'device:${device.id}',
      () => _admin.signOutDevice(_user.id, device.id),
      done: l10n.signedOutDone,
    );
  }

  Future<void> _unenroll(AdminEnrollment enrollment) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.removeFromCourse,
      message: l10n.removeFromCourseConfirm,
      confirmLabel: l10n.remove,
      destructive: true,
    );
    if (!confirmed) return;
    await _run(
      'course:${enrollment.courseId}',
      () => _admin.unenroll(_user.id, enrollment.courseId),
      done: l10n.removed,
    );
  }

  Future<void> _enroll() async {
    final enrolled = {for (final e in widget.detail.enrollments) e.courseId};
    final course = await showDialog<AdminCourse>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (_) => _CoursePicker(exclude: enrolled),
    );
    if (course == null || !mounted) return;
    await _run('enroll', () => _admin.enroll(_user.id, course.id), done: context.l10n.enrolled);
  }

  Future<void> _toggleSuspended() async {
    final l10n = context.l10n;
    final suspending = _user.status != 'suspended';
    if (suspending) {
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.suspendUser,
        message: l10n.suspendConfirm,
        confirmLabel: l10n.suspendUser,
        destructive: true,
      );
      if (!confirmed) return;
    }
    await _run(
      'status',
      () => _admin.updateUser(_user.id, status: suspending ? 'suspended' : 'active'),
      done: suspending ? l10n.suspended : l10n.activated,
    );
  }

  Future<void> _setPassword() async {
    final result = await showDialog<(String, bool)>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (_) => const _SetPasswordDialog(),
    );
    if (result == null || !mounted) return;
    final (password, mustChange) = result;
    await _run(
      'password',
      () => _admin.updateUser(_user.id, password: password, mustChangePassword: mustChange),
      done: context.l10n.passwordSetDone,
    );
  }

  Future<void> _edit() async {
    final result = await showDialog<(String, String)>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (_) => _EditUserDialog(name: _user.displayName ?? '', role: _user.role),
    );
    if (result == null || !mounted) return;
    final (name, role) = result;
    await _run(
      'edit',
      () => _admin.updateUser(
        _user.id,
        displayName: name == (_user.displayName ?? '') ? null : name,
        role: role == _user.role ? null : role,
      ),
      done: context.l10n.saved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final detail = widget.detail;
    final name = _user.displayName?.trim();
    final title = name == null || name.isEmpty ? _user.phoneMasked : name;
    final signedIn = detail.devices.where((d) => d.signedIn).toList();
    final suspended = _user.status == 'suspended';

    return AppPage(
      back: widget.back,
      maxWidth: 820,
      onRefresh: () async => ref.invalidate(adminUserProvider(_user.id)),
      header: PageHeader(
        title: title,
        subtitle: MetaLine(items: [_user.phoneMasked, roleLabelOf(_user.role, l10n)]),
        actions: [
          AppButton(
            label: l10n.editUser,
            icon: AppIcons.edit,
            loading: _busy == 'edit',
            onPressed: _edit,
          ),
        ],
        bottom: Wrap(
          spacing: AppSpace.x2,
          runSpacing: AppSpace.x2,
          children: [
            AppBadge(
              label: suspended ? l10n.statusSuspended : l10n.statusActive,
              tone: suspended ? BadgeTone.danger : BadgeTone.success,
            ),
            if (_user.mustChangePassword)
              AppBadge(label: l10n.awaitingNewPassword, tone: BadgeTone.warning),
          ],
        ),
      ),
      slivers: [
        SliverToBoxAdapter(child: SectionHeader(title: l10n.deviceLimitLabel)),
        SliverToBoxAdapter(child: _LimitEditor(summary: _summary)),
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.signedInDevicesTitle,
            meta: l10n.signedInOf(
              JalaliFormat.toPersianDigits('${signedIn.length}'),
              JalaliFormat.toPersianDigits('${_summary.effectiveMaxDevices}'),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: signedIn.isEmpty
              ? _Quiet(l10n.noSignedInDevices)
              : AppListGroup(
                  children: [
                    for (final device in signedIn)
                      AppListRow(
                        title: device.name,
                        leading: IconTile(icon: deviceIcon(device.platform)),
                        subtitle: MetaLine(
                          items: [
                            if (device.signedInAt != null)
                              l10n.signedInSince(JalaliFormat.relative(device.signedInAt!)),
                            if (device.lastSeenAt != null)
                              l10n.lastSeen(JalaliFormat.relative(device.lastSeenAt!)),
                          ],
                          maxLines: 2,
                        ),
                        trailing: AppIconButton(
                          icon: AppIcons.signOut,
                          tooltip: l10n.signOutDevice,
                          loading: _busy == 'device:${device.id}',
                          hoverColor: context.colors.dangerSubtle,
                          onPressed: () => _signOutDevice(device),
                        ),
                      ),
                  ],
                ),
        ),
        SliverToBoxAdapter(
          child: SectionHeader(
            title: l10n.enrollmentsTitle,
            action: AppButton.ghost(
              label: l10n.enrollInCourse,
              icon: AppIcons.enroll,
              size: AppButtonSize.small,
              loading: _busy == 'enroll',
              onPressed: _enroll,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: detail.enrollments.isEmpty
              ? _Quiet(l10n.noEnrollments)
              : AppListGroup(
                  children: [
                    for (final e in detail.enrollments)
                      AppListRow(
                        title: e.courseTitle,
                        leading: const IconTile(icon: AppIcons.course),
                        subtitle: MetaLine(
                          items: [
                            switch (e.status) {
                              'suspended' => l10n.enrollmentSuspended,
                              'completed' => l10n.enrollmentCompleted,
                              _ => l10n.statusActive,
                            },
                            if (e.expiresAt != null)
                              l10n.enrollmentExpires(JalaliFormat.longDate(e.expiresAt!)),
                          ],
                        ),
                        trailing: AppIconButton(
                          icon: AppIcons.remove,
                          tooltip: l10n.removeFromCourse,
                          loading: _busy == 'course:${e.courseId}',
                          hoverColor: context.colors.dangerSubtle,
                          onPressed: () => _unenroll(e),
                        ),
                      ),
                  ],
                ),
        ),
        SliverToBoxAdapter(child: SectionHeader(title: l10n.accountSection)),
        SliverToBoxAdapter(
          child: AppListGroup(
            children: [
              AppListRow(
                title: l10n.setPassword,
                leading: const IconTile(icon: AppIcons.code),
                trailing: _busy == 'password' ? const AppSpinner() : null,
                showChevron: true,
                onTap: _busy == null ? _setPassword : null,
              ),
              AppListRow(
                title: suspended ? l10n.activateUser : l10n.suspendUser,
                leading: IconTile(icon: suspended ? AppIcons.activate : AppIcons.suspend),
                destructive: !suspended,
                trailing: _busy == 'status' ? const AppSpinner() : null,
                onTap: _busy == null ? _toggleSuspended : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.textTertiary),
    ),
  );
}

/// This account's device limit: the institute default, or its own number.
class _LimitEditor extends ConsumerStatefulWidget {
  const _LimitEditor({required this.summary});

  final AdminUser summary;

  @override
  ConsumerState<_LimitEditor> createState() => _LimitEditorState();
}

class _LimitEditorState extends ConsumerState<_LimitEditor> {
  /// An own limit being edited; null while it matches the server.
  int? _draft;
  bool _saving = false;

  Future<void> _save({int? limit}) async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateUser(widget.summary.user.id, maxDevices: limit, clearMaxDevices: limit == null);
      ref
        ..invalidate(adminUserProvider(widget.summary.user.id))
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
    final own = widget.summary.maxDevices;
    final defaultLimit = ref.watch(instituteSettingsProvider).value?.defaultMaxDevices;
    final custom = _draft != null || own != null;
    final value = _draft ?? own ?? widget.summary.effectiveMaxDevices;

    return AppSurface(
      padding: const EdgeInsets.all(AppSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpace.x3,
            runSpacing: AppSpace.x3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppSegmented<bool>(
                value: custom,
                onChanged: (wantCustom) {
                  if (_saving || wantCustom == custom) return;
                  if (wantCustom) {
                    setState(() => _draft = widget.summary.effectiveMaxDevices);
                  } else if (own == null) {
                    setState(() => _draft = null);
                  } else {
                    _save();
                  }
                },
                segments: [
                  AppSegment(
                    value: false,
                    label: l10n.useInstituteDefault(
                      JalaliFormat.toPersianDigits(
                        '${defaultLimit ?? widget.summary.effectiveMaxDevices}',
                      ),
                    ),
                  ),
                  AppSegment(value: true, label: l10n.customLimit),
                ],
              ),
              if (custom)
                LimitStepper(
                  value: value,
                  onChanged: _saving ? null : (v) => setState(() => _draft = v == own ? null : v),
                ),
              if (_draft != null)
                AppButton.primary(
                  label: l10n.save,
                  loading: _saving,
                  onPressed: () => _save(limit: _draft),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.x3),
          Text(
            l10n.limitLoweredHint,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Picks a course to enroll in, from those the account is not in yet.
class _CoursePicker extends ConsumerWidget {
  const _CoursePicker({required this.exclude});

  final Set<String> exclude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final courses = ref.watch(adminCoursesProvider);

    return AppDialog(
      title: l10n.enrollInCourse,
      maxWidth: 480,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: courses.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpace.x6),
            child: Center(child: AppSpinner()),
          ),
          error: (error, _) =>
              ErrorView(error: error, onRetry: () => ref.invalidate(adminCoursesProvider)),
          data: (items) {
            final available = items.where((c) => !exclude.contains(c.id)).toList();
            if (available.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.x4),
                child: Text(l10n.noCoursesToEnroll),
              );
            }
            return SingleChildScrollView(
              child: AppListGroup(
                children: [
                  for (final course in available)
                    AppListRow(
                      title: course.title,
                      leading: const IconTile(icon: AppIcons.course),
                      subtitle: l10n.adminEnrolledCount(
                        JalaliFormat.toPersianDigits('${course.enrolledCount}'),
                      ),
                      showChevron: true,
                      onTap: () => Navigator.of(context).pop(course),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A new password set by the admin. Returns the password and whether the student must replace it.
class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog();

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _password = TextEditingController(text: generateTemporaryPassword());
  bool _mustChange = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    // The phone is not known here (the admin sees it masked); the server checks that rule.
    final problem = passwordProblem(_password.text, null, context.l10n);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop((_password.text, _mustChange));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      title: l10n.setPassword,
      actions: [
        AppButton(label: l10n.cancel, onPressed: () => Navigator.of(context).pop()),
        AppButton.primary(label: l10n.save, onPressed: _submit),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.x3),
          AppTextField(
            controller: _password,
            label: l10n.temporaryPassword,
            errorText: _error,
            autofocus: true,
            prefixIcon: AppIcons.code,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            inputFormatters: [LengthLimitingTextInputFormatter(128)],
            onSubmitted: (_) => _submit(),
            suffix: AppIconButton(
              icon: AppIcons.generate,
              tooltip: l10n.generatePassword,
              size: AppButtonSize.small,
              onPressed: () => setState(() => _password.text = generateTemporaryPassword()),
            ),
          ),
          CheckboxListTile(
            value: _mustChange,
            onChanged: (v) => setState(() => _mustChange = v ?? true),
            title: Text(l10n.mustChangeAtFirstSignIn),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// Name and role. Returns both; unchanged values are not sent.
class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.name, required this.role});

  final String name;
  final String role;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final _name = TextEditingController(text: widget.name);
  late String _role = widget.role;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.nameRequired);
      return;
    }
    Navigator.of(context).pop((name, _role));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      title: l10n.editUser,
      actions: [
        AppButton(label: l10n.cancel, onPressed: () => Navigator.of(context).pop()),
        AppButton.primary(label: l10n.save, onPressed: _submit),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.x3),
          AppTextField(
            controller: _name,
            label: l10n.displayNameLabel,
            errorText: _error,
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpace.x4),
          Text(l10n.roleLabel, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpace.x2),
          AppSegmented<String>(
            value: _role,
            expand: true,
            onChanged: (role) => setState(() => _role = role),
            segments: [
              AppSegment(value: 'student', label: l10n.roleStudent),
              AppSegment(value: 'teacher', label: l10n.roleTeacher),
              AppSegment(value: 'admin', label: l10n.roleAdmin),
            ],
          ),
        ],
      ),
    );
  }
}
