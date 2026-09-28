import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';

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

  void _changeNumber() => setState(() {
        _codeSent = false;
        _codeController.clear();
        _error = null;
      });

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
        showToast(context, e.messageFa, tone: ToastTone.danger);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;
    final compact = context.windowSize.isCompact;

    final form = Column(
      key: ValueKey(_codeSent),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_codeSent) _phoneField(l10n) else _codeField(l10n),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.x3),
          InlineAlert(message: _error!),
        ],
        const SizedBox(height: AppSpace.x5),
        AppButton.primary(
          label: _codeSent ? l10n.verifyCode : l10n.sendCode,
          size: AppButtonSize.large,
          expand: true,
          loading: _busy,
          onPressed: _codeSent ? _verify : _requestCode,
        ),
        if (_codeSent) ...[
          const SizedBox(height: AppSpace.x3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppButton.ghost(
                label: l10n.changeNumber,
                icon: AppIcons.back,
                size: AppButtonSize.small,
                onPressed: _busy ? null : _changeNumber,
              ),
              AppButton.ghost(
                label: _resendIn > 0
                    ? l10n.resendIn(JalaliFormat.toPersianDigits('$_resendIn'))
                    : l10n.resendCode,
                size: AppButtonSize.small,
                onPressed: _resendIn > 0 || _busy ? null : _requestCode,
              ),
            ],
          ),
        ],
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: Align(
          // On a phone the form sits high, clear of the keyboard; elsewhere it is centred.
          alignment: compact ? const Alignment(0, -0.4) : Alignment.center,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.x6, vertical: AppSpace.x8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandMark(size: 40)),
                  const SizedBox(height: AppSpace.x6),
                  Text(
                    l10n.signInTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpace.x2),
                  Text(
                    _codeSent ? l10n.codeSubtitle(_phoneController.text) : l10n.signInSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpace.x8),
                  AnimatedSwitcher(
                    duration: AppMotion.base,
                    switchInCurve: AppMotion.curve,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    child: form,
                  ),
                  const SizedBox(height: AppSpace.x8),
                  Text(
                    l10n.signInFooter,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneField(AppLocalizations l10n) => AppTextField(
        controller: _phoneController,
        autofocus: true,
        label: l10n.phoneLabel,
        hint: l10n.phoneHint,
        prefixIcon: AppIcons.phoneInput,
        size: AppTextFieldSize.large,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.go,
        autofillHints: const [AutofillHints.telephoneNumber],
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
        onSubmitted: (_) => _busy ? null : _requestCode(),
      );

  // One field rather than a box per digit: the code length is a server setting (4–8), and a single
  // field takes a pasted or autofilled code in one go.
  Widget _codeField(AppLocalizations l10n) => AppTextField(
        controller: _codeController,
        autofocus: true,
        label: l10n.codeLabel,
        size: AppTextFieldSize.large,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w500),
        inputFormatters: [
          LengthLimitingTextInputFormatter(8),
          FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩]')),
        ],
        onSubmitted: (_) => _busy ? null : _verify(),
      );
}
