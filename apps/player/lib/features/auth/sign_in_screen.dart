import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/jalali.dart';
import '../../l10n/l10n.dart';

/// Phone + OTP sign-in.
///
/// Two panes in one screen rather than two routes, so going back from the code entry returns to the
/// number without losing it — the commonest correction a student makes.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _requestCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await ref.read(authRepositoryProvider).requestOtp(_phoneController.text);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        // In development the server returns the code, so the field is prefilled and testing does not
        // need a real SMS gateway. In production devCode is always null.
        if (result.devCode != null) _codeController.text = result.devCode!;
      });
      _startResendCountdown(result.resendAfterSeconds);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.messageFa);
      // The server tells us how long to wait; reflecting it stops the student tapping into a longer
      // block.
      final retryAfter = e.details?['retryAfterSeconds'];
      if (retryAfter is int) _startResendCountdown(retryAfter);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final device = await ref.read(deviceIdentityProvider).describe();
      final session = await ref.read(authRepositoryProvider).verifyOtp(
            phone: _phoneController.text,
            code: _codeController.text,
            device: device,
          );

      // AuthRepository has already persisted the tokens.
      ref.read(authControllerProvider.notifier).signedIn(session);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.messageFa);

      // A student at the device limit needs somewhere to go, not just a refusal.
      if (e.needsDeviceManager && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.messageFa)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  Icon(Icons.school_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 24),
                  Text(
                    l10n.signInTitle,
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _codeSent ? l10n.codeSubtitle(_phoneController.text) : l10n.signInSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (!_codeSent) _phoneField(l10n) else _codeField(l10n),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _errorBanner(theme, _error!),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : (_codeSent ? _verify : _requestCode),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_codeSent ? l10n.verifyCode : l10n.sendCode),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _resendIn > 0 || _busy ? null : _requestCode,
                      child: Text(
                        _resendIn > 0
                            ? l10n.resendIn(JalaliFormat.toPersianDigits('$_resendIn'))
                            : l10n.resendCode,
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _codeSent = false;
                                _codeController.clear();
                                _error = null;
                              }),
                      child: Text(l10n.changeNumber),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneField(AppLocalizations l10n) => TextField(
        controller: _phoneController,
        autofocus: true,
        keyboardType: TextInputType.phone,
        // The number is data, not display text: LTR so the digits read in entry order, even inside an
        // RTL interface.
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        // Persian and Arabic-Indic digits are allowed through — the server normalises them, and
        // blocking them would reject what a Persian keyboard produces by default.
        inputFormatters: [
          LengthLimitingTextInputFormatter(16),
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+۰-۹٠-٩\s-]')),
        ],
        decoration: InputDecoration(labelText: l10n.phoneLabel, hintText: l10n.phoneHint),
        onSubmitted: (_) => _busy ? null : _requestCode(),
      );

  Widget _codeField(AppLocalizations l10n) => TextField(
        controller: _codeController,
        autofocus: true,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, letterSpacing: 8),
        inputFormatters: [
          LengthLimitingTextInputFormatter(8),
          FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩]')),
        ],
        decoration: InputDecoration(labelText: l10n.codeLabel),
        onSubmitted: (_) => _busy ? null : _verify(),
      );

  Widget _errorBanner(ThemeData theme, String message) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      );
}
