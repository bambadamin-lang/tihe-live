import 'dart:async';

import 'package:capture_guard/capture_guard.dart';
import 'package:flutter/material.dart';

/// Manual test bench for docs/11-live-classroom.md §12: start a screen recorder (OBS,
/// Snipping Tool, Cmd-Shift-5, Control Centre) and watch this screen censor itself.
void main() => runApp(const GuardDemo());

class GuardDemo extends StatefulWidget {
  const GuardDemo({super.key});

  @override
  State<GuardDemo> createState() => _GuardDemoState();
}

class _GuardDemoState extends State<GuardDemo> {
  late final CaptureMonitor _monitor;
  final _log = <String>[];
  StreamSubscription<CaptureReport>? _reports;

  @override
  void initState() {
    super.initState();
    _monitor = CaptureMonitor(
      platform: MethodChannelCaptureGuard(),
      engine: CapturePolicyEngine(
        recorderProcesses: const [
          'obs64.exe',
          'obs',
          'screencaptureui',
          'sharex.exe',
          'bdcam.exe',
        ],
      ),
      block: true,
      windowsAffinity: WindowsAffinity.monitor,
      iosSecureLayer: true,
    );
    _monitor.verdicts.listen((_) => setState(() {}));
    _reports = _monitor.reports.listen(
      (r) => setState(
        () => _log.insert(
          0,
          '${TimeOfDay.now().format(context)}  capturing=${r.capturing}  '
          '${r.signals.map((s) => s.wire).join(', ')}  ${r.detail ?? ''}',
        ),
      ),
    );
    _monitor.start().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    _reports?.cancel();
    _monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verdict = _monitor.verdict;
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text('capture_guard — ${_monitor.blockResult.mechanism}'),
          ),
          body: Column(
            children: [
              Expanded(
                child: verdict.censor
                    ? const ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: Text(
                            'ضبط صفحه در کلاس مجاز نیست',
                            style: TextStyle(color: Colors.white, fontSize: 24),
                          ),
                        ),
                      )
                    : const ColoredBox(
                        color: Color(0xFF2E7D32),
                        child: Center(
                          child: Text(
                            'محتوای محافظت‌شده کلاس',
                            style: TextStyle(color: Colors.white, fontSize: 32),
                          ),
                        ),
                      ),
              ),
              SizedBox(
                height: 160,
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [for (final line in _log) Text(line)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
