import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tihe_classroom/tihe_classroom.dart' show Glass;

import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';

/// Choosing a password: forced after an admin set one ([forced]), or from the account page.
///
/// The new password is typed twice, with the rule shown before anyone gets it wrong. Other devices
/// are signed out by default, because the usual reason to change a password is that someone else
/// knows it.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({this.forced = false, super.key});

  final bool forced;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _signOutOthers = true;
  bool _busy = false;
  bool _show = false;
  String? _error;
  String? _nextError;
  String? _repeatError;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    setState(() {
      _error = null;
      _nextError = [..._next.text.characters].length < 8 ? l10n.passwordTooShort : null;
      _repeatError = _repeat.text != _next.text ? l10n.passwordsDontMatch : null;
      if (_current.text.isEmpty) _error = l10n.fieldRequired;
    });
    if (_error != null || _nextError != null || _repeatError != null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(
            current: _current.text,
            next: _next.text,
            signOutOtherDevices: _signOutOthers,
          );
      if (!mounted) return;
      showToast(context, l10n.passwordChanged, tone: ToastTone.success);
      await ref.read(authControllerProvider.notifier).refreshSession();
      if (mounted && !widget.forced) context.pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.messageFa);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;

    Widget field(TextEditingController c, String label, {String? error, bool autofocus = false}) =>
        AppTextField(
          controller: c,
          label: label,
          errorText: error,
          autofocus: autofocus,
          obscureText: !_show,
          prefixIcon: AppIcons.code,
          size: AppTextFieldSize.large,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _busy ? null : _save(),
        );

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field(_current, l10n.currentPassword, autofocus: true),
        const SizedBox(height: AppSpace.x4),
        field(_next, l10n.newPassword, error: _nextError),
        const SizedBox(height: AppSpace.x2),
        Text(
          l10n.passwordRules,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpace.x4),
        field(_repeat, l10n.repeatPassword, error: _repeatError),
        const SizedBox(height: AppSpace.x3),
        CheckboxListTile(
          value: _show,
          onChanged: (v) => setState(() => _show = v ?? false),
          title: Text(l10n.showPassword, style: theme.textTheme.bodyMedium),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        CheckboxListTile(
          value: _signOutOthers,
          onChanged: (v) => setState(() => _signOutOthers = v ?? true),
          title: Text(l10n.signOutOtherDevices, style: theme.textTheme.bodyMedium),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (_error != null) ...[const SizedBox(height: AppSpace.x3), InlineAlert(message: _error!)],
        const SizedBox(height: AppSpace.x5),
        AppButton.primary(
          label: l10n.savePassword,
          size: AppButtonSize.large,
          expand: true,
          loading: _busy,
          onPressed: _save,
        ),
        if (widget.forced) ...[
          const SizedBox(height: AppSpace.x3),
          AppButton.ghost(
            label: l10n.signOut,
            icon: AppIcons.signOut,
            onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ],
    );

    if (!widget.forced) {
      return AppPage(
        back: BackTarget(label: l10n.accountTitle, fallbackLocation: '/account'),
        maxWidth: 460,
        header: PageHeader(title: l10n.changePasswordTitle),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.x5)),
          SliverToBoxAdapter(child: form),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.x5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Glass(
                radius: 24,
                strong: true,
                padding: const EdgeInsets.all(AppSpace.x6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(size: 40)),
                    const SizedBox(height: AppSpace.x5),
                    Text(
                      l10n.chooseOwnPasswordTitle,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpace.x2),
                    Text(
                      l10n.chooseOwnPasswordBody,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpace.x6),
                    form,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
