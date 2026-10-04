import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/phone.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import 'limit_stepper.dart';

/// Creates an account. Returns the new user's id, or null if cancelled.
Future<String?> showAddUserDialog(BuildContext context) => showDialog<String>(
  context: context,
  barrierColor: context.colors.scrim,
  builder: (_) => const _AddUserDialog(),
);

/// A temporary password an admin can read out over the phone: eight digits, from a secure source.
/// The student is asked to replace it at first sign-in.
String generateTemporaryPassword([Random? random]) {
  final source = random ?? Random.secure();
  while (true) {
    final digits = List.generate(8, (_) => source.nextInt(10)).join();
    // The server refuses a password of one repeated character; never offer one.
    if (digits.split('').toSet().length > 1) return digits;
  }
}

/// Why [password] would be refused, before asking the server: `checkPasswordPolicy` in
/// packages/crypto, rule for rule. Null when it is acceptable. The server still decides.
String? passwordProblem(String password, String? phoneE164, AppLocalizations l10n) {
  final chars = password.runes.toList();
  if (chars.length < 8) return l10n.passwordTooShort;
  if (chars.toSet().length == 1) return l10n.passwordOneCharacter;
  if (phoneE164 != null) {
    final digits = Phone.foldDigits(password).replaceAll(RegExp(r'\D'), '');
    final local = phoneE164.replaceFirst('+98', '0');
    final national = phoneE164.replaceFirst('+98', '');
    if (digits.length >= 10 && (local.contains(digits) || digits.contains(national))) {
      return l10n.passwordIsPhone;
    }
  }
  return null;
}

class _AddUserDialog extends ConsumerStatefulWidget {
  const _AddUserDialog();

  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController(text: generateTemporaryPassword());
  String _role = 'student';
  bool _mustChange = true;
  int? _limit;
  bool _busy = false;
  String? _nameError;
  String? _phoneError;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = context.l10n;
    final phone = Phone.normalize(_phone.text);
    setState(() {
      _error = null;
      _nameError = _name.text.trim().isEmpty ? l10n.nameRequired : null;
      _phoneError = phone == null ? l10n.phoneInvalid : null;
      _passwordError = passwordProblem(_password.text, phone, l10n);
    });
    if (_nameError != null || _phoneError != null || _passwordError != null) return;

    setState(() => _busy = true);
    try {
      final created = await ref
          .read(adminRepositoryProvider)
          .createUser(
            phone: phone!,
            displayName: _name.text.trim(),
            password: _password.text,
            role: _role,
            mustChangePassword: _mustChange,
            maxDevices: _limit,
          );
      if (!mounted) return;
      showToast(context, l10n.userCreated, tone: ToastTone.success);
      Navigator.of(context).pop(created.summary.user.id);
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
    final defaultLimit = ref.watch(instituteSettingsProvider).value?.defaultMaxDevices;

    return AppDialog(
      title: l10n.addUser,
      maxWidth: 480,
      actions: [
        AppButton(label: l10n.cancel, onPressed: _busy ? null : () => Navigator.of(context).pop()),
        AppButton.primary(label: l10n.create, loading: _busy, onPressed: _create),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.x3),
          AppTextField(
            controller: _name,
            label: l10n.displayNameLabel,
            errorText: _nameError,
            autofocus: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpace.x4),
          AppTextField(
            controller: _phone,
            label: l10n.phoneLabel,
            hint: l10n.phoneHint,
            errorText: _phoneError,
            prefixIcon: AppIcons.phoneInput,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpace.x4),
          Text(l10n.roleLabel, style: theme.textTheme.labelLarge),
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
          const SizedBox(height: AppSpace.x4),
          AppTextField(
            controller: _password,
            label: l10n.temporaryPassword,
            errorText: _passwordError,
            prefixIcon: AppIcons.code,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            inputFormatters: [LengthLimitingTextInputFormatter(128)],
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
            title: Text(l10n.mustChangeAtFirstSignIn, style: theme.textTheme.bodyMedium),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          const SizedBox(height: AppSpace.x2),
          Text(l10n.deviceLimitLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpace.x2),
          Wrap(
            spacing: AppSpace.x3,
            runSpacing: AppSpace.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppSegmented<bool>(
                value: _limit != null,
                onChanged: (custom) =>
                    setState(() => _limit = custom ? (_limit ?? defaultLimit ?? 2) : null),
                segments: [
                  AppSegment(
                    value: false,
                    label: l10n.useInstituteDefault(
                      defaultLimit == null ? '…' : JalaliFormat.toPersianDigits('$defaultLimit'),
                    ),
                  ),
                  AppSegment(value: true, label: l10n.customLimit),
                ],
              ),
              if (_limit != null)
                LimitStepper(value: _limit!, onChanged: (v) => setState(() => _limit = v)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.x4),
            InlineAlert(message: _error!),
          ],
        ],
      ),
    );
  }
}
