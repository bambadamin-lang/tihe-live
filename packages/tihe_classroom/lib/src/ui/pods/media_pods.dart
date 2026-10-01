import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../data/media.dart';
import '../../state/classroom_session.dart';
import '../../state/providers.dart';
import '../theme/glass.dart';
import 'people.dart';

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
          Center(
            child: Avatar(userId: userId, name: tile.name, size: 88),
          ),
        PositionedDirectional(
          start: 10,
          bottom: 10,
          end: 10,
          child: Align(
            alignment: AlignmentDirectional.bottomStart,
            child: NameStrip(
              name: tile.name,
              micOn: tile.mic,
              speaking: tile.speaking,
              hand: tile.hand,
            ),
          ),
        ),
      ],
    );
  }
}

/// Everyone on camera, in a grid sized to the pod. Adaptive streaming on the LiveKit side
/// means off-screen tiles cost nothing.
///
/// The grid watches only who is in it and in what order; each tile watches its own person, so
/// a speaking change redraws two tiles, not the gallery.
class GalleryPod extends ConsumerWidget {
  const GalleryPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    if (people.isEmpty) return const _Empty(text: 'هنوز کسی در کلاس نیست');
    return LayoutBuilder(
      builder: (context, box) {
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
              for (final userId in shown)
                SizedBox(
                  key: ValueKey(userId),
                  width: best.width,
                  height: best.width * 9 / 16,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _Tile(userId: userId),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = ref.watch(
      classroomViewProvider.select((v) => _tileOf(v, userId)),
    );
    final session = ref.watch(classroomSessionProvider);
    return SpeakingFrame(
      speaking: tile.speaking,
      child: ColoredBox(
        color: const Color(0xFF16181E),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (tile.camera)
              session.media.video(userId, VideoSlot.camera)
            else
              Center(
                child: LayoutBuilder(
                  builder: (context, box) => Avatar(
                    userId: userId,
                    name: tile.name,
                    size: min(56, box.maxHeight * 0.55),
                  ),
                ),
              ),
            PositionedDirectional(
              start: 5,
              bottom: 5,
              end: 5,
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: NameStrip(
                  name: tile.name,
                  micOn: tile.mic,
                  speaking: tile.speaking,
                  hand: tile.hand,
                ),
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
          mic: v.media.of(sharer).micOn,
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
          top: 8,
          start: 8,
          child: NameStrip(name: 'صفحهٔ ${s.name}', micOn: s.mic),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, this.icon = ClassroomIcons.cameraOff});

  final String text;
  final IconData icon;

  // On the dark inset screen in both themes, so the colours are fixed rather than themed.
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, size: 20, color: Colors.white54),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 13.5),
        ),
      ],
    ),
  );
}
