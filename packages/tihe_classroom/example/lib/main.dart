import 'dart:io' show Platform;

import 'package:flutter/material.dart';
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
void main() => runApp(const ClassroomExampleApp());

class ClassroomExampleApp extends StatelessWidget {
  const ClassroomExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TIHE Live — کلاس',
    debugShowCheckedModeBanner: false,
    locale: const Locale('fa'),
    supportedLocales: const [Locale('fa'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildClassroomThemeData(),
    home: const Launcher(),
  );
}

class Launcher extends StatefulWidget {
  const Launcher({super.key});

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

  void _open(ClassroomSession session) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ClassroomPage(
        session: session,
        onExit: (_) => Navigator.of(context).pop(),
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: t.woodDark,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: BrassPlate(
                      child: Text(
                        'تیهه لایو — کلاس آنلاین',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 250,
                    child: PaperCard(
                      title: 'کلاس نمایشی (بدون سرور)',
                      inset: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<String>(
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
                            decoration: const InputDecoration(
                              labelText: 'چیدمان آغازین',
                              border: OutlineInputBorder(),
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
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _demo,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('ورود به کلاس نمایشی'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 340,
                    child: PaperCard(
                      title: 'اتصال به سرور',
                      inset: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _server,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'نشانی services/live',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _session,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'شناسهٔ جلسه (ses_…)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _token,
                            textDirection: TextDirection.ltr,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'توکن دسترسی',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: t.ledRed,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _joining ? null : _connect,
                            icon: const Icon(Icons.login),
                            label: Text(
                              _joining ? 'در حال ورود…' : 'ورود به کلاس',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
