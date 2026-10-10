import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/tihe_classroom.dart';
import 'package:window_manager/window_manager.dart';

import 'updater.dart';

/// The classroom on its own, for development and for the device checklist in
/// docs/11-live-classroom.md §12:
///
/// - **Demo**: a lecture in progress, served in-process — no server, no LiveKit.
/// - **Server**: joins a real session on services/live (see services/live/README.md for a
///   development token and a class to start).
///
/// Desktop development shortcut: with TIHE_LIVE_URL, TIHE_SESSION and TIHE_TOKEN set, the app
/// joins that session straight away.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The installed Windows app updates itself from GitHub releases (updater.dart). An update
  // downloaded on an earlier run is installed before the window ever shows: the wizard draws
  // its own progress bar and starts the app again when it is done.
  final updates = Platform.isWindows && appVersion.isNotEmpty
      ? AppUpdates(
          Updater(
            currentVersion: appVersion,
            directory: defaultUpdateDirectory(),
          ),
        )
      : null;
  if (updates != null && await updates.installPendingOnStart()) exit(0);
  updates?.start();
  // Many Android phones run apps at 60 Hz unless they ask for more; ask for the display's
  // fastest mode so the class animates at 90/120 Hz where the screen can. Desktop and iOS
  // already follow the display (iOS via CADisableMinimumFrameDurationOnPhone).
  if (Platform.isAndroid) {
    unawaited(
      FlutterDisplayMode.setHighRefreshRate().catchError((Object _) {}),
    );
  }
  // On Windows the app draws its own title bar. Set before the first frame, which is when the
  // runner shows the window, so the system bar never flashes up.
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setMinimumSize(const Size(960, 620));
  }
  // Modam before the first frame, so no text is ever drawn in a fallback font first.
  await ClassroomFonts.ensureLoaded();
  runApp(ClassroomExampleApp(updates: updates));
}

/// Follows the system's light or dark mode until the user picks one, here or in class.
class ClassroomExampleApp extends StatefulWidget {
  const ClassroomExampleApp({
    super.key,
    this.ping = LiveApi.reachable,
    this.updates,
  });

  /// Checks the class server for the status lamp; replaced in tests.
  final Future<bool> Function(String baseUrl) ping;

  /// Self-update on an installed Windows build; null elsewhere.
  final AppUpdates? updates;

  @override
  State<ClassroomExampleApp> createState() => _ClassroomExampleAppState();
}

class _ClassroomExampleAppState extends State<ClassroomExampleApp> {
  ThemeMode _mode = ThemeMode.system;

  void _setBrightness(Brightness b) => setState(
    () => _mode = b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TIHE Live — کلاس',
    debugShowCheckedModeBanner: false,
    locale: const Locale('fa'),
    supportedLocales: const [Locale('fa'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildClassroomThemeData(ClassroomTheme.light),
    darkTheme: buildClassroomThemeData(ClassroomTheme.dark),
    themeMode: _mode,
    // The brand cursor everywhere, dialogs included; on Windows, the app's own window frame.
    builder: (context, child) => GlowCursorScope(
      child: Platform.isWindows
          ? _WindowFrame(child: child!)
          : child ?? const SizedBox.shrink(),
    ),
    home: Launcher(
      onBrightnessChanged: _setBrightness,
      ping: widget.ping,
      updates: widget.updates,
    ),
  );
}

/// Window buttons and dragging for the title bars the app draws itself (Windows).
class _WindowFrame extends StatefulWidget {
  const _WindowFrame({required this.child});

  final Widget child;

  @override
  State<_WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<_WindowFrame> with WindowListener {
  bool _maximised = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximised = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximised = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximised = false);

  @override
  Widget build(BuildContext context) => WindowChrome(
    controls: WindowButtons(
      maximised: _maximised,
      onMinimise: windowManager.minimize,
      onMaximise: () =>
          _maximised ? windowManager.unmaximize() : windowManager.maximize(),
      onClose: windowManager.close,
    ),
    // Pan only: a double-tap recogniser here would hold every click on the bar's buttons.
    dragArea: (bar) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: bar,
    ),
    child: widget.child,
  );
}

class Launcher extends StatefulWidget {
  const Launcher({
    super.key,
    required this.onBrightnessChanged,
    this.ping = LiveApi.reachable,
    this.updates,
  });

  final ValueChanged<Brightness> onBrightnessChanged;
  final Future<bool> Function(String baseUrl) ping;
  final AppUpdates? updates;

  @override
  State<Launcher> createState() => _LauncherState();
}

enum _ServerState { checking, online, offline }

class _LauncherState extends State<Launcher> {
  final _server = TextEditingController(text: 'http://localhost:3100/v1/live');
  final _session = TextEditingController();
  final _token = TextEditingController();
  String _as = DemoClassroom.host;
  LayoutPreset _layout = LayoutPreset.whiteboard;
  String? _error;
  bool _joining = false;

  _ServerState _serverState = _ServerState.checking;
  Timer? _recheck;
  Timer? _debounce;
  int _pingGeneration = 0;

  @override
  void initState() {
    super.initState();
    final installed = _installedServer();
    if (installed != null) _server.text = installed;
    final env = Platform.environment;
    final url = env['TIHE_LIVE_URL'],
        session = env['TIHE_SESSION'],
        token = env['TIHE_TOKEN'];
    if (url != null && session != null && token != null) {
      _server.text = url;
      _session.text = session;
      _token.text = token;
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
    _server.addListener(_serverEdited);
    _check();
    // The lamp stays honest while the launcher sits open.
    _recheck = Timer.periodic(const Duration(seconds: 20), (_) => _check());
  }

  @override
  void dispose() {
    _recheck?.cancel();
    _debounce?.cancel();
    _server.dispose();
    _session.dispose();
    _token.dispose();
    super.dispose();
  }

  void _serverEdited() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _check);
  }

  Future<void> _check() async {
    final generation = ++_pingGeneration;
    if (_serverState != _ServerState.checking) {
      setState(() => _serverState = _ServerState.checking);
    }
    final ok = await widget.ping(_server.text);
    // An older answer for an address since edited is not news.
    if (!mounted || generation != _pingGeneration) return;
    setState(
      () => _serverState = ok ? _ServerState.online : _ServerState.offline,
    );
  }

  void _open(ClassroomSession session) => Navigator.of(context).push(
    classroomRoute<void>(
      context,
      (_) => ClassroomPage(
        session: session,
        onExit: (_) => Navigator.of(context).pop(),
        // The class follows this app's theme; a switch made in class carries back here.
        onBrightnessChanged: widget.onBrightnessChanged,
      ),
    ),
  );

  void _demo() {
    final demo = DemoClassroom.build(
      as: _as,
      layout: layoutPresets[_layout],
      hostSharing:
          _layout == LayoutPreset.presentation || _layout == LayoutPreset.split,
    );
    _open(demo.session);
  }

  Future<void> _connect() async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final session = await openClassroom(
        liveApiBaseUrl: _server.text.trim(),
        accessToken: () async => _token.text.trim(),
        sessionId: _session.text.trim(),
      );
      _open(session);
    } on ApiError catch (e) {
      setState(() => _error = e.messageFa);
    } on Object catch (e) {
      setState(() => _error = 'اتصال برقرار نشد: $e');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final dark = t.isDark;
    final chrome = WindowChrome.maybeOf(context);
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final (lampColor, lampLabel) = switch (_serverState) {
      _ServerState.checking => (t.warning, 'در حال بررسی'),
      _ServerState.online => (t.success, 'آنلاین'),
      _ServerState.offline => (t.danger, 'سرور در دسترس نیست'),
    };

    // The brand and the server lamp at the physical left, the window buttons at the right —
    // where Windows keeps them in every language.
    final titleBar = Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 6),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            const BrandLockup(),
            const BarDivider(height: 26),
            Tooltip(
              message: 'وضعیت سرور کلاس‌ها',
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: StatusPill(
                  color: lampColor,
                  label: lampLabel,
                  pulsing: _serverState == _ServerState.checking,
                ),
              ),
            ),
            const Spacer(),
            ?chrome?.controls,
          ],
        ),
      ),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: GlassBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                chrome == null ? titleBar : chrome.dragArea(titleBar),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        narrow ? 16 : 24,
                        8,
                        narrow ? 16 : 24,
                        28,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(
                              dark: dark,
                              narrow: narrow,
                              onToggle: () => widget.onBrightnessChanged(
                                dark ? Brightness.light : Brightness.dark,
                              ),
                            ),
                            SizedBox(height: narrow ? 18 : 24),
                            if (widget.updates case final updates?)
                              ListenableBuilder(
                                listenable: updates,
                                builder: (context, _) =>
                                    switch (updates.ready) {
                                      final ready? => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 18,
                                        ),
                                        child: Appear(
                                          offset: const Offset(0, 16),
                                          child: _UpdateNote(
                                            version: ready.version,
                                            onInstall: updates.installNow,
                                          ),
                                        ),
                                      ),
                                      null => const SizedBox.shrink(),
                                    },
                              ),
                            Appear(
                              offset: const Offset(0, 16),
                              child: _Card(
                                icon: ClassroomIcons.play,
                                title: 'کلاس نمایشی',
                                hint:
                                    'بدون سرور، فقط برای تجربه و آشنایی با فضای کلاس اجرا می‌شود.',
                                children: [
                                  GlassTabs<String>(
                                    expand: true,
                                    selected: _as,
                                    onSelected: (v) => setState(() => _as = v),
                                    options: const [
                                      (
                                        value: DemoClassroom.host,
                                        label: 'میزبان',
                                        icon: ClassroomIcons.person,
                                      ),
                                      (
                                        value: DemoClassroom.cohost,
                                        label: 'دستیار',
                                        icon: ClassroomIcons.assistant,
                                      ),
                                      (
                                        value: DemoClassroom.ali,
                                        label: 'دانشجو',
                                        icon: ClassroomIcons.person,
                                      ),
                                    ],
                                  ),
                                  _LayoutField(
                                    value: _layout,
                                    onChanged: (p) =>
                                        setState(() => _layout = p),
                                  ),
                                  GlowButton(
                                    label: 'ورود به کلاس نمایشی',
                                    icon: ClassroomIcons.play,
                                    onPressed: _demo,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Appear(
                              delay: const Duration(milliseconds: 80),
                              offset: const Offset(0, 16),
                              child: _Card(
                                icon: ClassroomIcons.server,
                                title: 'اتصال به سرور',
                                hint:
                                    // Isolated and joined, so the path stays whole and in one line.
                                    'ورود به سرور جلسات واقعی روی \u2066services/\u2060live\u2069.',
                                children: [
                                  _Field(
                                    icon: ClassroomIcons.link,
                                    label: 'نشانی سرور',
                                    controller: _server,
                                  ),
                                  _Field(
                                    icon: ClassroomIcons.hash,
                                    label: 'شناسهٔ جلسه (ses_…)',
                                    controller: _session,
                                  ),
                                  _Field(
                                    icon: ClassroomIcons.key,
                                    label: 'توکن دسترسی',
                                    controller: _token,
                                    obscure: true,
                                  ),
                                  if (_error != null) _ErrorNote(_error!),
                                  GlowButton(
                                    label: _joining
                                        ? 'در حال ورود…'
                                        : 'ورود به کلاس',
                                    icon: ClassroomIcons.join,
                                    busy: _joining,
                                    onPressed: _joining ? null : _connect,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's name with its mark, centred, and the light/dark switch at the end.
class _Header extends StatelessWidget {
  const _Header({
    required this.dark,
    required this.narrow,
    required this.onToggle,
  });

  final bool dark;
  final bool narrow;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final toggle = Glass(
      radius: 999,
      shadow: false,
      padding: const EdgeInsets.all(3),
      child: GlassIconButton(
        icon: dark ? ClassroomIcons.light : ClassroomIcons.dark,
        tooltip: dark ? 'پوستهٔ روشن' : 'پوستهٔ تیره',
        size: 42,
        iconSize: 20,
        radius: 999,
        onPressed: onToggle,
      ),
    );
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 56 : 64),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTile(
                  icon: ClassroomIcons.play,
                  size: narrow ? 44 : 54,
                  solid: true,
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'تیهه لایو — کلاس آنلاین',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: narrow ? 21 : 28,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: t.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          PositionedDirectional(end: 0, child: toggle),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.hint,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Glass(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconTile(icon: icon, size: 58),
            ],
          ),
          for (final child in children) ...[const SizedBox(height: 16), child],
        ],
      ),
    );
  }
}

/// A text field in the design's shape: icon and label at the start, the value (which is Latin
/// — addresses, ids, tokens) at the end.
class _Field extends StatefulWidget {
  const _Field({
    required this.icon,
    required this.label,
    required this.controller,
    this.obscure = false,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool obscure;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final focused = _focus.hasFocus;
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        height: 56,
        padding: const EdgeInsetsDirectional.only(start: 18, end: 18),
        decoration: BoxDecoration(
          color: t.field,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: focused ? t.accent : t.fieldBorder,
            width: focused ? 1.5 : 1,
          ),
          boxShadow: focused ? t.accentGlow(strength: 0.35) : null,
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 20,
              color: focused ? t.accentText : t.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: TextStyle(fontSize: 14.5, color: t.textSecondary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Semantics(
                label: widget.label,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  obscureText: widget.obscure,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 15.5, color: t.text),
                  decoration: const InputDecoration(
                    filled: false,
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The starting layout, as a field that opens a glass menu of the six presets.
class _LayoutField extends StatelessWidget {
  const _LayoutField({required this.value, required this.onChanged});

  final LayoutPreset value;
  final ValueChanged<LayoutPreset> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      semanticLabel: 'چیدمان آغازین: ${layoutPresets[value]!.name}',
      radius: 15,
      onTap: () async {
        final chosen = await showGlassMenu<LayoutPreset>(
          context: context,
          width: null,
          entries: [
            for (final p in LayoutPreset.values)
              GlassMenuItem(
                value: p,
                label: layoutPresets[p]!.name,
                checked: p == value,
              ),
          ],
        );
        if (chosen != null) onChanged(chosen);
      },
      builder: (context, s) => AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        height: 60,
        padding: const EdgeInsetsDirectional.only(start: 18, end: 16),
        decoration: BoxDecoration(
          color: s.hovered ? Color.alphaBlend(t.glassHover, t.field) : t.field,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: t.fieldBorder),
        ),
        child: Row(
          children: [
            Icon(ClassroomIcons.screen, size: 20, color: t.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'چیدمان آغازین',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: t.textTertiary,
                    ),
                  ),
                  Text(
                    layoutPresets[value]!.name,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ],
              ),
            ),
            Icon(ClassroomIcons.chevronDown, size: 20, color: t.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// A new version is downloaded and checked. Installing now closes the app for a few seconds;
/// otherwise it is installed the next time the app opens.
class _UpdateNote extends StatelessWidget {
  const _UpdateNote({required this.version, required this.onInstall});

  final String version;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: t.accentSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(ClassroomIcons.update, size: 18, color: t.accentText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'نسخهٔ تازهٔ برنامه (${toPersianDigits(version)}) آماده است. اگر الان نصب '
                  'نکنید، دفعهٔ بعد که برنامه را باز کنید خودش نصب می‌شود.',
                  style: TextStyle(
                    color: t.text,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GlowButton(
            label: 'نصب و اجرای دوباره',
            icon: ClassroomIcons.update,
            height: 42,
            onPressed: onInstall,
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: t.dangerSubtle,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: t.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ClassroomIcons.alert, size: 18, color: t.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: t.danger,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The server the Windows installer was given (installer/windows/tihe_live.iss writes it next
/// to the executable), so a student never has to type it.
String? _installedServer() {
  try {
    final file = File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}tihe_live.json',
    );
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync());
    final url = json is Map ? json['liveApiBaseUrl'] : null;
    return url is String && url.isNotEmpty ? url : null;
  } on Object {
    // A damaged file only costs the pre-filled address.
    return null;
  }
}
