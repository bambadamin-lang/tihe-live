import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tihe_classroom/tihe_classroom.dart' show WindowButtons, WindowChrome;
import 'package:window_manager/window_manager.dart';

/// Whether the app draws its own title bar: on Windows, where the system's would be a grey strip
/// over the night sky (docs/11 §11). Every screen then shows the window buttons itself — the
/// welcome page and the shell in their title bars, the player and the class in their top bars.
final bool ownsWindowFrame = !kIsWeb && Platform.isWindows;

/// Hides the system title bar. Before the first frame, which is when the runner shows the window,
/// so the system bar never flashes up.
Future<void> setUpWindowFrame() async {
  if (!ownsWindowFrame) return;
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
}

/// Window buttons and dragging for the title bars the app draws itself ([WindowChrome]).
class AppWindowFrame extends StatefulWidget {
  const AppWindowFrame({required this.child, super.key});

  final Widget child;

  @override
  State<AppWindowFrame> createState() => _AppWindowFrameState();
}

class _AppWindowFrameState extends State<AppWindowFrame> with WindowListener {
  bool _maximised = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximised = value);
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
      onMaximise: () => _maximised ? windowManager.unmaximize() : windowManager.maximize(),
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

/// A bare title bar for a screen with nothing else to put in one: the window buttons at the
/// physical right, the rest a handle to drag the window by. Empty unless the app draws its own
/// frame.
class WindowBar extends StatelessWidget {
  const WindowBar({super.key});

  @override
  Widget build(BuildContext context) {
    final chrome = WindowChrome.maybeOf(context);
    if (chrome == null) return const SizedBox.shrink();
    return chrome.dragArea(
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [const Spacer(), chrome.controls]),
        ),
      ),
    );
  }
}
