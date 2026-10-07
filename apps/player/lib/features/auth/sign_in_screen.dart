import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tihe_classroom/demo.dart' show DemoClassroom;
import 'package:tihe_classroom/tihe_classroom.dart' as live;

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
import '../live/classroom_launcher.dart';

/// The welcome page (docs/11 §11): phone + password sign-in (ADR-0013), and the demo class.
///
/// The classroom package's welcome page, as in the standalone classroom: the brand and the
/// server's lamp in the title bar, then two cards — signing in, with the server's address beside
/// the phone and password, and the demo class, which needs no server at all. At the device limit
/// (ADR-0014) the screen does not dead-end: it lists the devices signed in and signs one out on a
/// tap, without asking for the password again.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

enum _Lamp { checking, online, offline }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final _server = TextEditingController(
    text: ref.read(serverProvider).serverUrl.replaceFirst('http://', ''),
  );
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _busy = false;
  bool _showPassword = false;
  String? _serverError;
  String? _phoneError;
  String? _passwordError;
  String? _error;
  int _waitSeconds = 0;
  Timer? _waitTimer;

  String _demoAs = DemoClassroom.host;
  live.LayoutPreset _demoLayout = live.LayoutPreset.whiteboard;

  _Lamp _lamp = _Lamp.checking;
  Timer? _recheck;
  Timer? _debounce;
  int _pingGeneration = 0;

  @override
  void initState() {
    super.initState();
    _server.addListener(_serverEdited);
    _check();
    // The lamp stays honest while the page sits open.
    _recheck = Timer.periodic(const Duration(seconds: 20), (_) => _check());
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _recheck?.cancel();
    _debounce?.cancel();
    _server.dispose();
    _phone.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _serverEdited() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _check);
  }

  Future<void> _check() async {
    final generation = ++_pingGeneration;
    final url = ServerConfig.normalize(_server.text);
    if (url == null) return setState(() => _lamp = _Lamp.offline);
    if (_lamp != _Lamp.checking) setState(() => _lamp = _Lamp.checking);
    final ok = await ref.read(serverPingProvider)(ServerConfig(url).apiBaseUrl);
    // An older answer, for an address since edited, is not news.
    if (!mounted || generation != _pingGeneration) return;
    setState(() => _lamp = ok ? _Lamp.online : _Lamp.offline);
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
    final server = ServerConfig.normalize(_server.text);
    final phone = Phone.normalize(_phone.text);
    setState(() {
      _error = null;
      _serverError = server == null ? l10n.serverInvalid : null;
      _phoneError = _phone.text.trim().isEmpty
          ? l10n.fieldRequired
          : (phone == null ? l10n.phoneInvalid : null);
      _passwordError = _password.text.isEmpty ? l10n.fieldRequired : null;
    });
    if (server == null || phone == null || _phoneError != null || _passwordError != null) return;

    setState(() => _busy = true);
    try {
      // The address the student typed is the one signed in to, and remembered.
      if (server != ref.read(serverProvider).serverUrl) {
        await ref.read(serverProvider.notifier).set(server);
      }
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;
    final glass = live.ClassroomTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final (lampColor, lampLabel) = switch (_lamp) {
      _Lamp.checking => (glass.warning, l10n.serverChecking),
      _Lamp.online => (glass.success, l10n.serverOnline),
      _Lamp.offline => (glass.danger, l10n.serverOffline),
    };
    final waiting = _waitSeconds > 0;

    return live.WelcomePage(
      // The app paints the sky behind every route.
      backdrop: false,
      title: l10n.signInTitle,
      onToggleBrightness: () =>
          ref.read(themeModeProvider.notifier).set(dark ? ThemeMode.light : ThemeMode.dark),
      status: Tooltip(
        message: l10n.serverStatus,
        child: live.StatusPill(
          color: lampColor,
          label: lampLabel,
          pulsing: _lamp == _Lamp.checking,
        ),
      ),
      cards: [
        live.WelcomeCard(
          icon: AppIcons.account,
          title: l10n.accountTitle,
          hint: l10n.signInSubtitle,
          children: [
            AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  live.WelcomeField(
                    icon: AppIcons.server,
                    label: l10n.serverLabel,
                    controller: _server,
                    error: _serverError,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) =>
                        _serverError == null ? null : setState(() => _serverError = null),
                  ),
                  const SizedBox(height: 16),
                  live.WelcomeField(
                    icon: AppIcons.phoneInput,
                    label: l10n.phoneLabel,
                    hint: l10n.phoneHint,
                    controller: _phone,
                    autofocus: true,
                    error: _phoneError,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.username],
                    // Persian and Arabic-Indic digits pass: they are what a Persian keyboard types.
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(16),
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+۰-۹٠-٩\s-]')),
                    ],
                    onChanged: (_) =>
                        _phoneError == null ? null : setState(() => _phoneError = null),
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 16),
                  live.WelcomeField(
                    icon: AppIcons.code,
                    label: l10n.passwordLabel,
                    controller: _password,
                    focusNode: _passwordFocus,
                    obscure: !_showPassword,
                    error: _passwordError,
                    textInputAction: TextInputAction.go,
                    autofillHints: const [AutofillHints.password],
                    trailing: live.GlassIconButton(
                      icon: _showPassword ? AppIcons.hidePassword : AppIcons.showPassword,
                      tooltip: _showPassword ? l10n.hidePassword : l10n.showPassword,
                      size: 36,
                      iconSize: 18,
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                    onChanged: (_) =>
                        _passwordError == null ? null : setState(() => _passwordError = null),
                    onSubmitted: (_) => _busy || waiting ? null : _signIn(),
                  ),
                ],
              ),
            ),
            if (_error != null)
              live.WelcomeNote(
                waiting
                    ? '$_error ${l10n.retryAfter(JalaliFormat.toPersianDigits('$_waitSeconds'))}'
                    : _error!,
              ),
            live.GlowButton(
              label: l10n.signInButton,
              icon: live.ClassroomIcons.join,
              busy: _busy,
              onPressed: _busy || waiting ? null : _signIn,
            ),
            Text(
              l10n.forgotPasswordHint,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        live.WelcomeCard(
          icon: live.ClassroomIcons.play,
          title: l10n.demoTitle,
          hint: l10n.demoSubtitle,
          children: [
            live.GlassTabs<String>(
              expand: true,
              selected: _demoAs,
              onSelected: (as) => setState(() => _demoAs = as),
              options: [
                (value: DemoClassroom.host, label: l10n.demoAsHost, icon: AppIcons.teacher),
                (value: DemoClassroom.cohost, label: l10n.demoAsCohost, icon: AppIcons.users),
                (value: DemoClassroom.ali, label: l10n.demoAsStudent, icon: AppIcons.account),
              ],
            ),
            live.WelcomeLayoutField(
              value: _demoLayout,
              onChanged: (layout) => setState(() => _demoLayout = layout),
            ),
            live.GlowButton(
              label: l10n.demoEnter,
              icon: live.ClassroomIcons.play,
              onPressed: _busy
                  ? null
                  : () => openDemoClass(context, as: _demoAs, layout: _demoLayout),
            ),
          ],
        ),
      ],
    );
  }
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

/// Whether the app knows it is signed in with a temporary password.
bool mustChoosePassword(AuthState auth) =>
    auth is AuthSignedIn && auth.session.user.mustChangePassword;
