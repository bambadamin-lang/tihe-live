import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tihe_classroom/tihe_classroom.dart' show Glass;

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/api/repositories.dart';
import '../../core/phone.dart';
import '../../core/preferences.dart';
import '../../core/providers.dart';
import '../../core/server.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import '../devices/device_icon.dart';

/// Phone + password sign-in (ADR-0013).
///
/// One card, two fields, one button: the student types what the institute gave them and presses
/// Enter. At the device limit (ADR-0014) the screen does not dead-end: it lists the devices signed
/// in and signs one out on a tap, without asking for the password again.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _busy = false;
  bool _showPassword = false;
  String? _phoneError;
  String? _passwordError;
  String? _error;
  int _waitSeconds = 0;
  Timer? _waitTimer;

  @override
  void dispose() {
    _waitTimer?.cancel();
    _phone.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _startWait(int seconds) {
    _waitTimer?.cancel();
    setState(() => _waitSeconds = seconds);
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _waitSeconds -= 1);
      if (_waitSeconds <= 0) timer.cancel();
    });
  }

  Future<void> _signIn() async {
    final l10n = context.l10n;
    final phone = Phone.normalize(_phone.text);
    setState(() {
      _error = null;
      _phoneError = _phone.text.trim().isEmpty
          ? l10n.fieldRequired
          : (phone == null ? l10n.phoneInvalid : null);
      _passwordError = _password.text.isEmpty ? l10n.fieldRequired : null;
    });
    if (_phoneError != null || _passwordError != null || phone == null) return;

    setState(() => _busy = true);
    try {
      final device = await ref.read(deviceIdentityProvider).describe();
      final session = await ref
          .read(authRepositoryProvider)
          .login(phone: phone, password: _password.text, device: device);
      ref.read(authControllerProvider.notifier).signedIn(session);
    } on DeviceLimitReached catch (limit) {
      if (mounted) await _chooseDeviceToSignOut(limit.limit);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.messageFa);
      final wait = e.retryAfterSeconds;
      if (wait != null) _startWait(wait);
      if (e.code == 'INVALID_CREDENTIALS') {
        _password.clear();
        _passwordFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDeviceToSignOut(DeviceLimit limit) async {
    final chosen = await showDialog<Device>(
      context: context,
      builder: (_) => _DeviceLimitDialog(limit: limit),
    );
    if (chosen == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final device = await ref.read(deviceIdentityProvider).describe();
      final session = await ref
          .read(authRepositoryProvider)
          .replaceDevice(ticket: limit.ticket, signOutDeviceId: chosen.id, device: device);
      ref.read(authControllerProvider.notifier).signedIn(session);
    } on DeviceLimitReached catch (again) {
      // Someone else took the slot meanwhile, or the limit was lowered: ask again.
      if (mounted) await _chooseDeviceToSignOut(again.limit);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.messageFa);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editServer() async {
    await showDialog<void>(context: context, builder: (_) => const _ServerDialog());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;
    final compact = context.windowSize.isCompact;
    final server = ref.watch(serverProvider);
    final themeMode = ref.watch(themeModeProvider);
    final dark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    final card = Glass(
      radius: 24,
      strong: true,
      padding: const EdgeInsets.fromLTRB(AppSpace.x6, AppSpace.x8, AppSpace.x6, AppSpace.x6),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: BrandMark(size: 44)),
            const SizedBox(height: AppSpace.x5),
            Text(
              l10n.signInTitle,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.x2),
            Text(
              l10n.signInSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.x6),
            AppTextField(
              controller: _phone,
              autofocus: true,
              label: l10n.phoneLabel,
              hint: l10n.phoneHint,
              prefixIcon: AppIcons.phoneInput,
              size: AppTextFieldSize.large,
              errorText: _phoneError,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.username],
              // The number is data, not display text: LTR so the digits read in entry order.
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              // Persian and Arabic-Indic digits pass: they are what a Persian keyboard types.
              inputFormatters: [
                LengthLimitingTextInputFormatter(16),
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+۰-۹٠-٩\s-]')),
              ],
              onChanged: (_) => _phoneError == null ? null : setState(() => _phoneError = null),
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: AppSpace.x4),
            AppTextField(
              controller: _password,
              focusNode: _passwordFocus,
              label: l10n.passwordLabel,
              prefixIcon: AppIcons.code,
              size: AppTextFieldSize.large,
              errorText: _passwordError,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.go,
              autofillHints: const [AutofillHints.password],
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              suffix: AppIconButton(
                icon: _showPassword ? AppIcons.hidePassword : AppIcons.showPassword,
                tooltip: _showPassword ? l10n.hidePassword : l10n.showPassword,
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              onChanged: (_) =>
                  _passwordError == null ? null : setState(() => _passwordError = null),
              onSubmitted: (_) => _busy || _waitSeconds > 0 ? null : _signIn(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.x4),
              InlineAlert(
                message: _waitSeconds > 0
                    ? '$_error ${l10n.retryAfter(JalaliFormat.toPersianDigits('$_waitSeconds'))}'
                    : _error!,
              ),
            ],
            const SizedBox(height: AppSpace.x5),
            AppButton.primary(
              label: l10n.signInButton,
              size: AppButtonSize.large,
              expand: true,
              loading: _busy,
              onPressed: _waitSeconds > 0 ? null : _signIn,
            ),
            const SizedBox(height: AppSpace.x4),
            Text(
              l10n.forgotPasswordHint,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              // On a phone the form sits high, clear of the keyboard; elsewhere it is centred.
              alignment: compact ? const Alignment(0, -0.5) : Alignment.center,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.x5, vertical: AppSpace.x8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      card,
                      const SizedBox(height: AppSpace.x5),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpace.x2,
                        runSpacing: AppSpace.x2,
                        children: [
                          AppButton.ghost(
                            label: l10n.serverCurrent(_hostOf(server.serverUrl)),
                            icon: AppIcons.server,
                            size: AppButtonSize.small,
                            onPressed: _busy ? null : _editServer,
                          ),
                          AppButton.ghost(
                            label: l10n.tryDemo,
                            icon: AppIcons.demo,
                            size: AppButtonSize.small,
                            onPressed: _busy ? null : () => context.push('/demo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: AppSpace.x3,
              left: AppSpace.x3,
              child: AppIconButton(
                icon: dark ? AppIcons.themeLight : AppIcons.themeDark,
                tooltip: dark ? l10n.themeLight : l10n.themeDark,
                onPressed: () => ref
                    .read(themeModeProvider.notifier)
                    .set(dark ? ThemeMode.light : ThemeMode.dark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _hostOf(String url) => url.replaceFirst(RegExp(r'^https?://'), '');
}

/// The devices signed in at the limit, one to sign out. Returns the chosen device.
class _DeviceLimitDialog extends StatefulWidget {
  const _DeviceLimitDialog({required this.limit});

  final DeviceLimit limit;

  @override
  State<_DeviceLimitDialog> createState() => _DeviceLimitDialogState();
}

class _DeviceLimitDialogState extends State<_DeviceLimitDialog> {
  Device? _chosen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final theme = Theme.of(context);

    return AppDialog(
      title: l10n.deviceLimitTitle(JalaliFormat.toPersianDigits('${widget.limit.limit}')),
      maxWidth: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.deviceLimitBody,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpace.x4),
          RadioGroup<Device>(
            groupValue: _chosen,
            onChanged: (value) => setState(() => _chosen = value),
            child: AppListGroup(
              children: [
                for (final device in widget.limit.devices)
                  AppListRow(
                    leading: IconTile(icon: deviceIcon(device.platform)),
                    title: device.name,
                    subtitle: device.signedInAt == null
                        ? null
                        : l10n.signedInSince(JalaliFormat.relative(device.signedInAt!)),
                    trailing: Radio<Device>(value: device),
                    selected: _chosen == device,
                    onTap: () => setState(() => _chosen = device),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        AppButton(label: l10n.cancel, onPressed: () => Navigator.of(context).pop()),
        AppButton.primary(
          label: l10n.signOutAndContinue,
          onPressed: _chosen == null ? null : () => Navigator.of(context).pop(_chosen),
        ),
      ],
    );
  }
}

class _ServerDialog extends ConsumerStatefulWidget {
  const _ServerDialog();

  @override
  ConsumerState<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends ConsumerState<_ServerDialog> {
  late final _controller = TextEditingController(
    text: ref.read(serverProvider).serverUrl.replaceFirst('http://', ''),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await ref.read(serverProvider.notifier).set(_controller.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = context.l10n.serverInvalid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      title: l10n.serverLabel,
      body: AppTextField(
        controller: _controller,
        autofocus: true,
        hint: l10n.serverHint,
        helper: l10n.serverHelp,
        errorText: _error,
        prefixIcon: AppIcons.server,
        keyboardType: TextInputType.url,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        AppButton(label: l10n.cancel, onPressed: () => Navigator.of(context).pop()),
        AppButton.primary(label: l10n.serverSave, onPressed: _save),
      ],
    );
  }
}

/// Whether the app knows it is signed in with a temporary password.
bool mustChoosePassword(AuthState auth) =>
    auth is AuthSignedIn && auth.session.user.mustChangePassword;
