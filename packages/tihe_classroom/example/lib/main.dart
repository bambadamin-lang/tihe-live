import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// The classroom on its own, for development and for the device checklist in
/// docs/11-live-classroom.md §12:
///
/// - **Demo**: a lecture in progress, served in-process — no server, no LiveKit.
/// - **Server**: joins a real session on services/live (see services/live/README.md for a
///   development token and a class to start).
///
/// Desktop development shortcut: with TIHE_LIVE_URL, TIHE_SESSION and TIHE_TOKEN set, the app
/// joins that session straight away.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Many Android phones run apps at 60 Hz unless they ask for more; ask for the display's
  // fastest mode so the class animates at 90/120 Hz where the screen can. Desktop and iOS
  // already follow the display (iOS via CADisableMinimumFrameDurationOnPhone).
  if (Platform.isAndroid) {
    unawaited(
      FlutterDisplayMode.setHighRefreshRate().catchError((Object _) {}),
    );
  }
  runApp(const ClassroomExampleApp());
}

/// Follows the system's light or dark mode until the user picks one, here or in class.
class ClassroomExampleApp extends StatefulWidget {
  const ClassroomExampleApp({super.key});

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
    home: Launcher(onBrightnessChanged: _setBrightness),
  );
}

class Launcher extends StatefulWidget {
  const Launcher({super.key, required this.onBrightnessChanged});

  final ValueChanged<Brightness> onBrightnessChanged;

  @override
  State<Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<Launcher> {
  final _server = TextEditingController(text: 'http://localhost:3100/v1/live');
  final _session = TextEditingController();
  final _token = TextEditingController();
  String _as = DemoClassroom.host;
  LayoutPreset _layout = LayoutPreset.whiteboard;
  String? _error;
  bool _joining = false;

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
  }

  @override
  void dispose() {
    _server.dispose();
    _session.dispose();
    _token.dispose();
    super.dispose();
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: GlassBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: t.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              ClassroomIcons.play,
                              size: 18,
                              color: t.onAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'تیهه لایو — کلاس آنلاین',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: t.text,
                              ),
                            ),
                          ),
                          Glass(
                            radius: 999,
                            shadow: false,
                            padding: const EdgeInsets.all(1),
                            child: GlassIconButton(
                              icon: dark
                                  ? ClassroomIcons.light
                                  : ClassroomIcons.dark,
                              tooltip: dark ? 'پوستهٔ روشن' : 'پوستهٔ تیره',
                              size: 34,
                              onPressed: () => widget.onBrightnessChanged(
                                dark ? Brightness.light : Brightness.dark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _Section(
                        title: 'کلاس نمایشی',
                        hint:
                            'بدون سرور؛ طرف دیگر کلاس در خود برنامه اجرا می‌شود.',
                        children: [
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: DemoClassroom.host,
                                label: Text('میزبان'),
                              ),
                              ButtonSegment(
                                value: DemoClassroom.cohost,
                                label: Text('دستیار'),
                              ),
                              ButtonSegment(
                                value: DemoClassroom.ali,
                                label: Text('دانشجو'),
                              ),
                            ],
                            selected: {_as},
                            onSelectionChanged: (s) =>
                                setState(() => _as = s.first),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<LayoutPreset>(
                            initialValue: _layout,
                            borderRadius: BorderRadius.circular(12),
                            decoration: const InputDecoration(
                              labelText: 'چیدمان آغازین',
                            ),
                            items: [
                              for (final p in LayoutPreset.values)
                                DropdownMenuItem(
                                  value: p,
                                  child: Text(layoutPresets[p]!.name),
                                ),
                            ],
                            onChanged: (p) =>
                                setState(() => _layout = p ?? _layout),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _demo,
                            icon: const Icon(ClassroomIcons.play, size: 16),
                            label: const Text('ورود به کلاس نمایشی'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _Section(
                        title: 'اتصال به سرور',
                        hint: 'ورود به جلسه‌ای واقعی روی services/live.',
                        children: [
                          TextField(
                            controller: _server,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'نشانی services/live',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _session,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'شناسهٔ جلسه (ses_…)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _token,
                            textDirection: TextDirection.ltr,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'توکن دسترسی',
                            ),
                          ),
                          if (_error != null)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: t.dangerSubtle,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: t.danger,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _joining ? null : _connect,
                            icon: const Icon(ClassroomIcons.join, size: 16),
                            label: Text(
                              _joining ? 'در حال ورود…' : 'ورود به کلاس',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.hint,
    required this.children,
  });

  final String title;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Glass(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(hint, style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
          const SizedBox(height: 16),
          ...children,
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
