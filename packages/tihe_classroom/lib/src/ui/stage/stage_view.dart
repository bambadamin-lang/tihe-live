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
class StageView extends ConsumerStatefulWidget {
  const StageView({super.key});

  @override
  ConsumerState<StageView> createState() => _StageViewState();
}

class _StageViewState extends ConsumerState<StageView> {
  String? _maximised;
  String? _tab;

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(
      classroomViewProvider.select((v) => v.room?.layout),
    );
    if (layout == null) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (StageGeometry.isCompact(size)) return _compact(layout);

        final maximised = layout.pods
            .where((p) => p.id == _maximised)
            .firstOrNull;
        if (maximised != null) {
          return Padding(
            padding: const EdgeInsets.all(4),
            child: _pod(maximised, maximised: true),
          );
        }
        final rects = StageGeometry.grid(
          layout,
          size,
          direction: Directionality.of(context),
        );
        return Stack(
          children: [
            for (final pod in layout.pods)
              AnimatedPositioned.fromRect(
                key: ValueKey(pod.kind),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
                rect: rects[pod.id]!,
                child: _pod(pod),
              ),
          ],
        );
      },
    );
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
            child: _pod(current, compact: true),
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

  // Every pod is its own layer: a new chat message or a live stroke on the board repaints that
  // pod, not the whole stage.
  Widget _pod(Pod pod, {bool maximised = false, bool compact = false}) =>
      RepaintBoundary(
        child: _podContent(pod, maximised: maximised, compact: compact),
      );

  Widget _podContent(Pod pod, {bool maximised = false, bool compact = false}) {
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
