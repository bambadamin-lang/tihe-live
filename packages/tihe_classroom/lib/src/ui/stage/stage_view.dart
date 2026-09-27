import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/stage_geometry.dart';
import '../../state/providers.dart';
import '../pods/chat_pod.dart';
import '../pods/hands_pod.dart';
import '../pods/media_pods.dart';
import '../pods/participants_pod.dart';
import '../theme/classroom_theme.dart';
import '../theme/skeuo.dart';
import '../whiteboard/whiteboard_pod.dart';

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
            padding: const EdgeInsets.all(6),
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
    final t = ClassroomTheme.of(context);
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: _pod(current, compact: true),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (final pod in tabs)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(pod.kind.labelFa),
                    selected: pod.id == current.id,
                    selectedColor: t.brassHigh,
                    backgroundColor: t.paperHigh,
                    onSelected: (_) => setState(() => _tab = pod.id),
                  ),
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
    // The whiteboard is its own physical object; everything else sits on a paper card.
    if (pod.kind == PodKind.whiteboard) {
      return _WithCorner(
        maximised: maximised,
        visible: !compact,
        onToggle: () => setState(() => _maximised = maximised ? null : pod.id),
        child: content,
      );
    }
    final screenLike = pod.kind.isMedia;
    return PaperCard(
      title: pod.kind.labelFa,
      inset: screenLike,
      trailing: compact
          ? null
          : _MaximiseButton(
              maximised: maximised,
              onPressed: () =>
                  setState(() => _maximised = maximised ? null : pod.id),
            ),
      child: content,
    );
  }
}

class _MaximiseButton extends StatelessWidget {
  const _MaximiseButton({required this.maximised, required this.onPressed});

  final bool maximised;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(6),
    child: Tooltip(
      message: maximised ? 'بازگشت به چیدمان' : 'بزرگ کردن',
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          maximised ? Icons.close_fullscreen : Icons.open_in_full,
          size: 15,
          color: ClassroomTheme.of(context).inkSoft,
        ),
      ),
    ),
  );
}

class _WithCorner extends StatelessWidget {
  const _WithCorner({
    required this.child,
    required this.maximised,
    required this.onToggle,
    required this.visible,
  });

  final Widget child;
  final bool maximised;
  final VoidCallback onToggle;
  final bool visible;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: child),
      if (visible)
        PositionedDirectional(
          top: 14,
          end: 16,
          child: Material(
            color: Colors.white.withValues(alpha: 0.7),
            shape: const CircleBorder(),
            child: _MaximiseButton(maximised: maximised, onPressed: onToggle),
          ),
        ),
    ],
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
