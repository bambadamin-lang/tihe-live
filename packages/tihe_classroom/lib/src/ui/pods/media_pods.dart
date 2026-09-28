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
/// whoever is talking — the same rule the recording template uses.
String? pickSpeaker(ClassroomView view) {
  final room = view.room;
  if (room == null) return null;
  final media = view.media;
  final ranked = room.participants.values.where((p) => p.online).toList()
    ..sort((a, b) => b.role.rank.compareTo(a.role.rank));
  for (final p in ranked) {
    if (p.role.rank >= ClassRole.presenter.rank &&
        media.of(p.userId).cameraOn) {
      return p.userId;
    }
  }
  final talking = media.activeSpeaker;
  if (talking != null && media.of(talking).cameraOn) return talking;
  for (final p in ranked) {
    if (media.of(p.userId).cameraOn) return p.userId;
  }
  // Nobody on camera: show the host's card.
  return ranked.isEmpty ? null : ranked.first.userId;
}

/// One person as a video tile shows them. Value-equal, so a tile rebuilds only when what it
/// draws changes — not on every event in the class.
typedef _Person = ({
  String userId,
  String name,
  bool hand,
  ParticipantMedia media,
});

class SpeakerPod extends ConsumerWidget {
  const SpeakerPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(classroomSessionProvider);
    final _Person? speaker = ref.watch(
      classroomViewProvider.select((v) {
        final userId = pickSpeaker(v);
        if (userId == null) return null;
        final p = v.room!.participants[userId];
        return (
          userId: userId,
          name: p?.name ?? '',
          hand: p?.hand != null,
          media: v.media.of(userId),
        );
      }),
    );
    if (speaker == null) return const _Empty(text: 'هنوز کسی در کلاس نیست');
    final media = speaker.media;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (media.cameraOn)
          session.media.video(speaker.userId, VideoSlot.camera)
        else
          Center(
            child: Avatar(userId: speaker.userId, name: speaker.name, size: 88),
          ),
        PositionedDirectional(
          start: 10,
          bottom: 10,
          end: 10,
          child: Align(
            alignment: AlignmentDirectional.bottomStart,
            child: NameStrip(
              name: speaker.name,
              micOn: media.micOn,
              speaking: media.speaking,
              hand: speaker.hand,
            ),
          ),
        ),
      ],
    );
  }
}

/// Everyone on camera, in a grid sized to the pod. Adaptive streaming on the LiveKit side
/// means off-screen tiles cost nothing.
class GalleryPod extends ConsumerWidget {
  const GalleryPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(classroomSessionProvider);
    final slice = ref.watch(
      classroomViewProvider.select((v) {
        final room = v.room;
        if (room == null) return null;
        final online = room.participants.values.where((p) => p.online).toList()
          ..sort((a, b) {
            final cam =
                (v.media.of(b.userId).cameraOn ? 1 : 0) -
                (v.media.of(a.userId).cameraOn ? 1 : 0);
            return cam != 0 ? cam : b.role.rank.compareTo(a.role.rank);
          });
        return ListSlice<_Person>([
          for (final p in online)
            (
              userId: p.userId,
              name: p.name,
              hand: p.hand != null,
              media: v.media.of(p.userId),
            ),
        ]);
      }),
    );
    if (slice == null) return const SizedBox.shrink();
    final people = slice.items;
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
              for (final p in shown)
                SizedBox(
                  key: ValueKey(p.userId),
                  width: best.width,
                  height: best.width * 9 / 16,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    // Each tile repaints on its own (video frames, the speaking ring) without
                    // taking the rest of the gallery with it.
                    child: RepaintBoundary(
                      child: _Tile(person: p, session: session),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.person, required this.session});

  final _Person person;
  final ClassroomSession session;

  @override
  Widget build(BuildContext context) => SpeakingFrame(
    speaking: person.media.speaking,
    child: ColoredBox(
      color: const Color(0xFF16181E),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (person.media.cameraOn)
            session.media.video(person.userId, VideoSlot.camera)
          else
            Center(
              child: LayoutBuilder(
                builder: (context, box) => Avatar(
                  userId: person.userId,
                  name: person.name,
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
                name: person.name,
                micOn: person.media.micOn,
                speaking: person.media.speaking,
                hand: person.hand,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ScreenPod extends ConsumerWidget {
  const ScreenPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(classroomSessionProvider);
    final share = ref.watch(
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
          micOn: v.media.of(sharer).micOn,
        );
      }),
    );
    if (share == null) {
      return const _Empty(
        text: 'اشتراک صفحه‌ای در جریان نیست',
        icon: ClassroomIcons.screen,
      );
    }
    if (share.mine) {
      // Showing your own screen back to you only makes a hall of mirrors.
      return const _Empty(
        text: 'صفحهٔ شما در حال اشتراک است',
        icon: ClassroomIcons.screenShare,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        session.media.video(
          share.sharer,
          VideoSlot.screen,
          fit: BoxFit.contain,
        ),
        PositionedDirectional(
          top: 8,
          start: 8,
          child: NameStrip(name: 'صفحهٔ ${share.name}', micOn: share.micOn),
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
