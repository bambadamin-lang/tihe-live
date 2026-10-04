import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../data/media.dart';
import '../../domain/persian.dart';
import '../../state/classroom_session.dart';
import '../../state/providers.dart';
import '../stage/stage_focus.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import '../theme/motion.dart';
import 'people.dart';
import 'person_actions.dart';

/// The pods that show video: speaker, gallery and screen share.

/// Who the speaker pod shows: the host (or a presenter) if their camera is on, otherwise
/// whoever is talking — the same rule the recording template uses. Equal ranks go to whoever
/// joined first.
String? pickSpeaker(ClassroomView view) {
  final room = view.room;
  if (room == null) return null;
  final media = view.media;
  // One pass in join order: this runs on every change in the class, for the speaker pod.
  ParticipantState? top, presenterOnCamera, onCamera;
  for (final p in room.participants.values) {
    if (!p.online) continue;
    final rank = p.role.rank;
    if (top == null || rank > top.role.rank) top = p;
    if (!media.of(p.userId).cameraOn) continue;
    if (rank >= ClassRole.presenter.rank &&
        (presenterOnCamera == null || rank > presenterOnCamera.role.rank)) {
      presenterOnCamera = p;
    }
    if (onCamera == null || rank > onCamera.role.rank) onCamera = p;
  }
  if (presenterOnCamera != null) return presenterOnCamera.userId;
  final talking = media.activeSpeaker;
  if (talking != null && media.of(talking).cameraOn) return talking;
  // Nobody senior on camera: whoever is, or else the host's card.
  return (onCamera ?? top)?.userId;
}

/// What a video tile shows of one person.
typedef _TileState = ({
  String name,
  bool camera,
  bool mic,
  bool speaking,
  bool hand,
});

_TileState _tileOf(ClassroomView v, String userId) {
  final p = v.room?.participants[userId];
  final m = v.media.of(userId);
  return (
    name: p?.name ?? '',
    camera: m.cameraOn,
    mic: m.micOn,
    speaking: m.speaking,
    hand: p?.hand != null,
  );
}

/// The speaker, edge to edge: a tag for the pod in one top corner, their name in the bottom one,
/// and — for managers — what they may do to them in the other.
class SpeakerPod extends ConsumerWidget {
  const SpeakerPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(
      classroomViewProvider.select((v) {
        final userId = pickSpeaker(v);
        return userId == null
            ? null
            : (userId: userId, tile: _tileOf(v, userId));
      }),
    );
    final session = ref.watch(classroomSessionProvider);
    if (s == null) return const _Empty(text: 'هنوز کسی در کلاس نیست');
    final (:userId, :tile) = s;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (tile.camera)
          session.media.video(userId, VideoSlot.camera)
        else
          _NoCamera(
            child: Avatar(userId: userId, name: tile.name, size: 96),
          ),
        const PositionedDirectional(
          top: 12,
          start: 12,
          child: _PodTag(icon: ClassroomIcons.pin, label: 'ارائه‌دهنده'),
        ),
        PositionedDirectional(
          start: 12,
          bottom: 12,
          end: 60,
          child: Align(
            alignment: AlignmentDirectional.bottomStart,
            child: NameStrip(
              name: tile.name,
              micOn: tile.mic,
              speaking: tile.speaking,
              hand: tile.hand,
              large: true,
            ),
          ),
        ),
        PositionedDirectional(
          bottom: 10,
          end: 10,
          child: ParticipantMenuButton(
            userId: userId,
            icon: ClassroomIcons.more,
            floating: true,
          ),
        ),
      ],
    );
  }
}

/// A small dark tag on the corner of a video pod.
class _PodTag extends StatelessWidget {
  const _PodTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF070C1A).withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white70),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Where a camera would be: a deep, softly lit card.
class _NoCamera extends StatelessWidget {
  const _NoCamera({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(0, -0.2),
        radius: 1.1,
        colors: [Color(0xFF1C2744), Color(0xFF0E1528)],
      ),
    ),
    child: Center(child: child),
  );
}

/// Everyone on camera. In a tall pod, a grid of the largest tiles that fit; in a short, wide
/// one, a film strip that scrolls. Adaptive streaming on the LiveKit side means off-screen
/// tiles cost nothing.
///
/// The gallery watches only who is in it and in what order; each tile watches its own person,
/// so a speaking change redraws two tiles, not the gallery. The order is stable for the same
/// reason: cameras first, then by role, never by who is talking.
class GalleryPod extends ConsumerStatefulWidget {
  const GalleryPod({super.key});

  @override
  ConsumerState<GalleryPod> createState() => _GalleryPodState();
}

class _GalleryPodState extends ConsumerState<GalleryPod> {
  final _strip = ScrollController();

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = ref
        .watch(
          classroomViewProvider.select((v) {
            final room = v.room;
            if (room == null) return null;
            final online =
                room.participants.values.where((p) => p.online).toList()
                  ..sort((a, b) {
                    final cam =
                        (v.media.of(b.userId).cameraOn ? 1 : 0) -
                        (v.media.of(a.userId).cameraOn ? 1 : 0);
                    return cam != 0 ? cam : b.role.rank.compareTo(a.role.rank);
                  });
            return ListValue([for (final p in online) p.userId]);
          }),
        )
        ?.items;
    if (people == null) return const SizedBox.shrink();
    if (people.isEmpty) {
      return const _Empty(text: 'هنوز کسی در کلاس نیست', dark: false);
    }
    Widget tile(String userId, {bool dense = false}) =>
        _Tile(key: ValueKey(userId), userId: userId, dense: dense);
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth / max(1, box.maxHeight) > 2.3) {
          return _filmstrip(context, box, people, tile);
        }
        // Largest tiles that fit: try column counts and keep the one with the biggest 16:9 tile.
        var best = (cols: 1, width: 0.0);
        for (var cols = 1; cols <= people.length; cols++) {
          final rows = (people.length / cols).ceil();
          final w = min(box.maxWidth / cols, box.maxHeight / rows * 16 / 9);
          if (w > best.width) best = (cols: cols, width: w);
        }
        final shown = people.take(
          max(1, (box.maxHeight / (best.width * 9 / 16)).floor() * best.cols),
        );
        return Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            children: [
              for (final p in shown)
                SizedBox(
                  width: best.width,
                  height: best.width * 9 / 16,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: tile(p),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _filmstrip(
    BuildContext context,
    BoxConstraints box,
    List<String> people,
    Widget Function(String, {bool dense}) tile,
  ) {
    const gap = 10.0, arrow = 34.0, pill = 36.0;
    int fits(double tileW, double width) =>
        max(1, ((width + gap) / (tileW + gap)).floor());
    var tileH = min(box.maxHeight, 150.0);
    var tileW = tileH * 1.36;
    final overflow = people.length > fits(tileW, box.maxWidth);
    if (overflow) {
      tileH = min(box.maxHeight - pill - 8, 150.0).clamp(48.0, 150.0);
      tileW = tileH * 1.36;
    }
    final room = box.maxWidth - (overflow ? 2 * (arrow + gap) : 0);
    final hidden = max(0, people.length - fits(tileW, room));
    final tiles = [
      for (final p in people)
        SizedBox(width: tileW, height: tileH, child: tile(p, dense: true)),
    ];
    if (!overflow) {
      return Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (i, t) in tiles.indexed) ...[
              if (i > 0) const SizedBox(width: gap),
              t,
            ],
          ],
        ),
      );
    }
    void page(int direction) {
      if (!_strip.hasClients) return;
      final to = (_strip.offset + direction * (room - tileW)).clamp(
        0.0,
        _strip.position.maxScrollExtent,
      );
      _strip.animateTo(
        to,
        duration: Motion.of(context, Motion.slow),
        curve: Motion.move,
      );
    }

    final t = ClassroomTheme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: tileH,
          child: Row(
            children: [
              GlassIconButton(
                icon: ClassroomIcons.previous,
                tooltip: 'قبلی',
                size: arrow,
                iconSize: 17,
                radius: 11,
                fill: t.field,
                onPressed: () => page(-1),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: ListView.separated(
                  controller: _strip,
                  scrollDirection: Axis.horizontal,
                  itemCount: tiles.length,
                  separatorBuilder: (_, _) => const SizedBox(width: gap),
                  itemBuilder: (_, i) => tiles[i],
                ),
              ),
              const SizedBox(width: gap),
              GlassIconButton(
                icon: ClassroomIcons.next,
                tooltip: 'بعدی',
                size: arrow,
                iconSize: 17,
                radius: 11,
                fill: t.field,
                onPressed: () => page(1),
              ),
            ],
          ),
        ),
        if (hidden > 0) ...[
          const SizedBox(height: 8),
          _MorePeople(count: hidden),
        ],
      ],
    );
  }
}

/// "+3 more": opens the gallery over the stage, where everyone fits.
class _MorePeople extends ConsumerWidget {
  const _MorePeople({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ClassroomTheme.of(context);
    final focus = StageFocusScope.maybeOf(context);
    final layout = ref.watch(
      classroomViewProvider.select((v) => v.room?.layout),
    );
    return GlassPressable(
      onTap: focus == null ? null : () => focus.toggle(PodKind.gallery, layout),
      semanticLabel: 'همهٔ تصاویر',
      radius: 12,
      builder: (context, s) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: s.hovered ? t.glassHover : t.field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.fieldBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ClassroomIcons.people, size: 16, color: t.textSecondary),
            const SizedBox(width: 8),
            Text(
              '+${toPersianDigits(count)} نفر دیگر',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({super.key, required this.userId, this.dense = false});

  final String userId;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = ref.watch(
      classroomViewProvider.select((v) => _tileOf(v, userId)),
    );
    final session = ref.watch(classroomSessionProvider);
    return SpeakingFrame(
      speaking: tile.speaking,
      child: ColoredBox(
        color: const Color(0xFF111A2E),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (tile.camera)
              session.media.video(userId, VideoSlot.camera)
            else
              _NoCamera(
                child: LayoutBuilder(
                  builder: (context, box) => Avatar(
                    userId: userId,
                    name: tile.name,
                    size: min(58, box.maxHeight * 0.42),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TileLabel(
                name: tile.name,
                micOn: tile.mic,
                speaking: tile.speaking,
                hand: tile.hand,
                dense: dense,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScreenPod extends ConsumerWidget {
  const ScreenPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(
      classroomViewProvider.select((v) {
        final hosts =
            v.room?.participants.values
                .where((p) => p.role.rank >= ClassRole.presenter.rank)
                .map((p) => p.userId) ??
            const <String>[];
        final sharer = v.media.screenSharer(preferred: hosts);
        if (sharer == null) return null;
        return (
          sharer: sharer,
          mine: sharer == v.userId,
          name: v.room?.participants[sharer]?.name ?? '',
        );
      }),
    );
    final session = ref.watch(classroomSessionProvider);
    if (s == null) {
      return const _Empty(
        text: 'اشتراک صفحه‌ای در جریان نیست',
        icon: ClassroomIcons.screen,
      );
    }
    if (s.mine) {
      // Showing your own screen back to you only makes a hall of mirrors.
      return const _Empty(
        text: 'صفحهٔ شما در حال اشتراک است',
        icon: ClassroomIcons.screenShare,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        session.media.video(s.sharer, VideoSlot.screen, fit: BoxFit.contain),
        PositionedDirectional(
          top: 12,
          start: 12,
          end: 60,
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: _PodTag(
              icon: ClassroomIcons.screen,
              label: 'صفحهٔ ${s.name}',
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.text,
    this.icon = ClassroomIcons.cameraOff,
    this.dark = true,
  });

  final String text;
  final IconData icon;

  /// On the dark inset screen (fixed colours) rather than on the pod's glass (themed).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final fg = dark ? Colors.white60 : t.textSecondary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.06) : t.field,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : t.fieldBorder,
              ),
            ),
            child: Icon(icon, size: 21, color: fg),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: fg, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
