import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../data/media.dart';
import '../../state/classroom_session.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
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

class SpeakerPod extends ConsumerWidget {
  const SpeakerPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(classroomViewProvider);
    final session = ref.watch(classroomSessionProvider);
    final userId = pickSpeaker(view);
    if (userId == null) return const _Empty(text: 'هنوز کسی در کلاس نیست');
    final p = view.room!.participants[userId];
    final media = view.media.of(userId);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (media.cameraOn)
          session.media.video(userId, VideoSlot.camera)
        else
          Center(
            child: Avatar(userId: userId, name: p?.name ?? '', size: 88),
          ),
        PositionedDirectional(
          start: 10,
          bottom: 10,
          end: 10,
          child: Align(
            alignment: AlignmentDirectional.bottomStart,
            child: NameStrip(
              name: p?.name ?? '',
              micOn: media.micOn,
              speaking: media.speaking,
              hand: p?.hand != null,
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
    final view = ref.watch(classroomViewProvider);
    final session = ref.watch(classroomSessionProvider);
    final room = view.room;
    if (room == null) return const SizedBox.shrink();
    final people = room.participants.values.where((p) => p.online).toList()
      ..sort((a, b) {
        final cam =
            (view.media.of(b.userId).cameraOn ? 1 : 0) -
            (view.media.of(a.userId).cameraOn ? 1 : 0);
        return cam != 0 ? cam : b.role.rank.compareTo(a.role.rank);
      });
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
                  width: best.width,
                  height: best.width * 9 / 16,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _Tile(
                      participant: p,
                      media: view.media.of(p.userId),
                      session: session,
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
  const _Tile({
    required this.participant,
    required this.media,
    required this.session,
  });

  final ParticipantState participant;
  final ParticipantMedia media;
  final ClassroomSession session;

  @override
  Widget build(BuildContext context) => SpeakingFrame(
    speaking: media.speaking,
    child: ColoredBox(
      color: const Color(0xFF221C16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media.cameraOn)
            session.media.video(participant.userId, VideoSlot.camera)
          else
            Center(
              child: LayoutBuilder(
                builder: (context, box) => Avatar(
                  userId: participant.userId,
                  name: participant.name,
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
                name: participant.name,
                micOn: media.micOn,
                speaking: media.speaking,
                hand: participant.hand != null,
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
    final view = ref.watch(classroomViewProvider);
    final session = ref.watch(classroomSessionProvider);
    final hosts =
        view.room?.participants.values
            .where((p) => p.role.rank >= ClassRole.presenter.rank)
            .map((p) => p.userId) ??
        const <String>[];
    final sharer = view.media.screenSharer(preferred: hosts);
    if (sharer == null) {
      return const _Empty(
        text: 'اشتراک صفحه‌ای در جریان نیست',
        icon: Icons.desktop_windows_outlined,
      );
    }
    if (sharer == view.userId) {
      // Showing your own screen back to you only makes a hall of mirrors.
      return const _Empty(
        text: 'صفحهٔ شما در حال اشتراک است',
        icon: Icons.screen_share,
      );
    }
    final name = view.room?.participants[sharer]?.name ?? '';
    return Stack(
      fit: StackFit.expand,
      children: [
        session.media.video(sharer, VideoSlot.screen, fit: BoxFit.contain),
        PositionedDirectional(
          top: 8,
          start: 8,
          child: NameStrip(
            name: 'صفحهٔ $name',
            micOn: view.media.of(sharer).micOn,
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, this.icon = Icons.videocam_off_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: t.paperEdge),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.paperLow, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
