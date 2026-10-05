import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/tihe_classroom.dart';
import 'package:window_manager/window_manager.dart';

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
  runApp(const ClassroomExampleApp());
}

/// Follows the system's light or dark mode until the user picks one, here or in class.
class ClassroomExampleApp extends StatefulWidget {
  const ClassroomExampleApp({super.key, this.ping = LiveApi.reachable});

  /// Checks the class server for the status lamp; replaced in tests.
  final Future<bool> Function(String baseUrl) ping;

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
    home: Launcher(onBrightnessChanged: _setBrightness, ping: widget.ping),
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
  });

  final ValueChanged<Brightness> onBrightnessChanged;
  final Future<bool> Function(String baseUrl) ping;

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
    final (lampColor, lampLabel) = switch (_serverState) {
      _ServerState.checking => (t.warning, 'در حال بررسی'),
      _ServerState.online => (t.success, 'آنلاین'),
      _ServerState.offline => (t.danger, 'سرور در دسترس نیست'),
    };

    return Directionality(
      textDirection: TextDirection.rtl,
      child: WelcomePage(
        title: 'تیهه لایو — کلاس آنلاین',
        onToggleBrightness: () => widget.onBrightnessChanged(
          dark ? Brightness.light : Brightness.dark,
        ),
        status: Tooltip(
          message: 'وضعیت سرور کلاس‌ها',
          child: StatusPill(
            color: lampColor,
            label: lampLabel,
            pulsing: _serverState == _ServerState.checking,
          ),
        ),
        cards: [
          WelcomeCard(
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
              WelcomeLayoutField(
                value: _layout,
                onChanged: (p) => setState(() => _layout = p),
              ),
              GlowButton(
                label: 'ورود به کلاس نمایشی',
                icon: ClassroomIcons.play,
                onPressed: _demo,
              ),
            ],
          ),
          WelcomeCard(
            icon: ClassroomIcons.server,
            title: 'اتصال به سرور',
            hint:
                // Isolated and joined, so the path stays whole and in one line.
                'ورود به سرور جلسات واقعی روی \u2066services/\u2060live\u2069.',
            children: [
              WelcomeField(
                icon: ClassroomIcons.link,
                label: 'نشانی سرور',
                controller: _server,
              ),
              WelcomeField(
                icon: ClassroomIcons.hash,
                label: 'شناسهٔ جلسه (ses_…)',
                controller: _session,
              ),
              WelcomeField(
                icon: ClassroomIcons.key,
                label: 'توکن دسترسی',
                controller: _token,
                obscure: true,
              ),
              if (_error != null) WelcomeNote(_error!),
              GlowButton(
                label: _joining ? 'در حال ورود…' : 'ورود به کلاس',
                icon: ClassroomIcons.join,
                busy: _joining,
                onPressed: _joining ? null : _connect,
              ),
            ],
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
