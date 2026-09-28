import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/stage_geometry.dart';
import '../../state/providers.dart';
import '../pods/chat_pod.dart';
import '../pods/hands_pod.dart';
import '../pods/media_pods.dart';
import '../pods/participants_pod.dart';
import '../theme/glass.dart';
import '../theme/motion.dart';
import '../whiteboard/whiteboard_pod.dart';

/// The icon each pod kind wears in its header, its tab and the layout picker.
const podIcons = {
  PodKind.speaker: ClassroomIcons.person,
  PodKind.gallery: ClassroomIcons.gallery,
  PodKind.screen: ClassroomIcons.screen,
  PodKind.whiteboard: ClassroomIcons.whiteboard,
  PodKind.chat: ClassroomIcons.chat,
  PodKind.participants: ClassroomIcons.people,
  PodKind.hands: ClassroomIcons.hand,
};

/// The stage: the host's layout, pod by pod (docs/11 §5). Wide screens show the whole 12 × 12
/// grid in reading direction; phones show one pod at a time behind tabs. A viewer can maximise
/// any pod on their own screen — that is local and never synced.
///
/// Motion: pods glide to their new places when the layout changes, new pods fade in and
/// removed ones fade out, maximise zooms the pod over the stage, and the first layout of the
/// class arrives pod by pod.
class StageView extends ConsumerStatefulWidget {
  const StageView({super.key});

  @override
  ConsumerState<StageView> createState() => _StageViewState();
}

typedef _Placed = ({Pod pod, Rect rect});

class _StageViewState extends ConsumerState<StageView> {
  String? _maximised;
  String? _tab;

  /// Where each pod was last drawn, to fade out the ones a new layout drops.
  Map<PodKind, _Placed> _last = {};
  final Map<PodKind, _Placed> _leaving = {};
  final Map<PodKind, Timer> _leaveTimers = {};

  /// False until the first layout has been shown: that one arrives pod by pod.
  bool _opened = false;

  @override
  void dispose() {
    for (final t in _leaveTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(
      classroomViewProvider.select((v) => v.room?.layout),
    );
    if (layout == null) return const SizedBox.expand();
    if (!_opened) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _opened = true);
    }
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (StageGeometry.isCompact(size)) return _compact(layout);
        final rects = StageGeometry.grid(
          layout,
          size,
          direction: Directionality.of(context),
        );
        _trackLeaving(layout, rects);

        final maximised = layout.pods
            .where((p) => p.id == _maximised)
            .firstOrNull;
        final full = (Offset.zero & size).deflate(4);
        final move = Motion.of(context, Motion.slow);
        final fade = Motion.of(context, Motion.medium);
        // The maximised pod paints last, so it zooms over the others as they fade.
        final order = [
          for (final p in layout.pods)
            if (p != maximised) p,
          ?maximised,
        ];
        return Stack(
          children: [
            for (final e in _leaving.entries)
              Positioned.fromRect(
                key: ValueKey(('leaving', e.key)),
                rect: e.value.rect,
                child: IgnorePointer(child: _Leave(child: _pod(e.value.pod))),
              ),
            for (final pod in order)
              AnimatedPositioned.fromRect(
                key: ValueKey(pod.kind),
                duration: move,
                curve: Motion.move,
                rect: pod == maximised ? full : rects[pod.id]!,
                child: IgnorePointer(
                  ignoring: maximised != null && pod != maximised,
                  child: AnimatedOpacity(
                    duration: fade,
                    curve: Motion.enter,
                    opacity: maximised != null && pod != maximised ? 0 : 1,
                    child: Appear(
                      delay: _opened
                          ? Duration.zero
                          : Duration(
                              milliseconds: 60 * layout.pods.indexOf(pod),
                            ),
                      duration: Motion.slow,
                      offset: const Offset(0, 14),
                      scale: 0.97,
                      child: _pod(pod, maximised: pod == maximised),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Keeps pods the new layout dropped on screen just long enough to fade out.
  void _trackLeaving(Layout layout, Map<String, Rect> rects) {
    final now = {
      for (final p in layout.pods) p.kind: (pod: p, rect: rects[p.id]!),
    };
    for (final kind in now.keys) {
      _leaving.remove(kind);
      _leaveTimers.remove(kind)?.cancel();
    }
    for (final e in _last.entries) {
      if (now.containsKey(e.key) || _leaving.containsKey(e.key)) continue;
      if (Motion.reduced(context)) continue;
      _leaving[e.key] = e.value;
      _leaveTimers[e.key] = Timer(Motion.medium, () {
        if (!mounted) return;
        setState(() {
          _leaving.remove(e.key);
          _leaveTimers.remove(e.key);
        });
      });
    }
    _last = now;
  }

  Widget _compact(Layout layout) {
    final tabs = StageGeometry.tabs(layout);
    final current = tabs.firstWhere(
      (p) => p.id == _tab,
      orElse: () => tabs.first,
    );
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.medium),
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(current.kind),
                child: _pod(current, compact: true),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
          child: GlassTabs<String>(
            selected: current.id,
            onSelected: (id) => setState(() => _tab = id),
            options: [
              for (final pod in tabs)
                (
                  value: pod.id,
                  label: pod.kind.labelFa,
                  icon: podIcons[pod.kind],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pod(Pod pod, {bool maximised = false, bool compact = false}) {
    final content = switch (pod.kind) {
      PodKind.speaker => const SpeakerPod(),
      PodKind.gallery => const GalleryPod(),
      PodKind.screen => const ScreenPod(),
      PodKind.whiteboard => const WhiteboardPod(),
      PodKind.chat => const ChatPod(),
      PodKind.participants => const ParticipantsPod(),
      PodKind.hands => const HandsPod(),
    };
    final maximise = compact
        ? null
        : _MaximiseButton(
            maximised: maximised,
            onPressed: () =>
                setState(() => _maximised = maximised ? null : pod.id),
          );
    // Each pod is its own layer: a video frame or a new message repaints that pod only.
    return RepaintBoundary(child: _panel(pod, content, maximise));
  }

  Widget _panel(Pod pod, Widget content, Widget? maximise) {
    // The board is its own surface: no header, the maximise control floats on its corner.
    if (pod.kind == PodKind.whiteboard) {
      return GlassPanel(
        padding: 6,
        child: Stack(
          children: [
            Positioned.fill(child: content),
            if (maximise != null)
              PositionedDirectional(top: 8, end: 8, child: maximise),
          ],
        ),
      );
    }
    return GlassPanel(
      title: pod.kind.labelFa,
      icon: podIcons[pod.kind],
      inset: pod.kind.isMedia,
      trailing: maximise,
      child: content,
    );
  }
}

/// A pod the layout dropped, fading and settling back as it goes.
class _Leave extends StatelessWidget {
  const _Leave({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 1, end: 0),
    duration: Motion.fast,
    curve: Motion.exit,
    child: child,
    builder: (context, v, child) => Opacity(
      opacity: v,
      child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
    ),
  );
}

class _MaximiseButton extends StatelessWidget {
  const _MaximiseButton({required this.maximised, required this.onPressed});

  final bool maximised;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => GlassIconButton(
    icon: maximised ? ClassroomIcons.restore : ClassroomIcons.maximise,
    tooltip: maximised ? 'بازگشت به چیدمان' : 'بزرگ کردن',
    size: 26,
    iconSize: 14,
    onPressed: onPressed,
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
