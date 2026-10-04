import 'package:flutter/widgets.dart';

import '../../contracts.dart';

/// What this viewer has brought forward on their own screen: a maximised pod, the phone's
/// current tab, or a side panel for a pod the host's layout leaves out. Local and never synced —
/// the layout itself is the host's (docs/11 §5).
class StageFocus extends ChangeNotifier {
  /// The pod zoomed over the stage, by id.
  String? get maximised => _maximised;
  String? _maximised;

  /// The pod a phone shows, by id; null for the layout's primary pod.
  String? get tab => _tab;
  String? _tab;

  /// A people pod the layout has no room for, open as a panel beside the stage.
  PodKind? get drawer => _drawer;
  PodKind? _drawer;

  /// Whether the stage is showing one pod at a time. Set by the stage as it lays out.
  bool compact = false;

  void maximise(String? podId) {
    if (_maximised == podId) return;
    _maximised = podId;
    notifyListeners();
  }

  void selectTab(String podId) {
    if (_tab == podId) return;
    _tab = podId;
    notifyListeners();
  }

  void closeDrawer() {
    if (_drawer == null) return;
    _drawer = null;
    notifyListeners();
  }

  /// The dock's chat and people keys: bring that pod forward, or put it away again. A pod in
  /// the layout is maximised (on a phone, its tab is shown); one that is not opens as a panel.
  void toggle(PodKind kind, Layout? layout) {
    final pod = layout?.pod(kind);
    if (pod == null) {
      _drawer = _drawer == kind ? null : kind;
    } else {
      _drawer = null;
      if (compact) {
        _tab = pod.id;
      } else {
        _maximised = _maximised == pod.id ? null : pod.id;
      }
    }
    notifyListeners();
  }

  /// Whether [kind] is the thing brought forward — the dock lights its key.
  bool isFocused(PodKind kind, Layout? layout) {
    if (_drawer == kind) return true;
    final pod = layout?.pod(kind);
    if (pod == null) return false;
    return compact ? _tab == pod.id : _maximised == pod.id;
  }
}

/// Hands the page's [StageFocus] to the stage and the dock.
class StageFocusScope extends InheritedNotifier<StageFocus> {
  const StageFocusScope({
    super.key,
    required StageFocus focus,
    required super.child,
  }) : super(notifier: focus);

  static StageFocus? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StageFocusScope>()?.notifier;
}
