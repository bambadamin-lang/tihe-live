import { Room, RoomEvent, Track, type Participant, type RemoteTrack } from 'livekit-client';
import type { RoomState } from '../../src/core/room-state.js';
import type { Stage } from './stage.js';

/** Most camera tiles a recorded gallery shows; beyond this the tiles are too small to matter. */
const GALLERY_MAX = 12;

/**
 * Puts LiveKit video into the recorded stage and plays every audio track so Egress captures
 * it. Who is "the speaker" comes from the classroom state (the host), not from LiveKit
 * metadata, so the recording follows the same roles as the live stage.
 */
export class MediaBinder {
  private readonly elements = new Map<string, HTMLMediaElement>();

  constructor(
    private readonly room: Room,
    private readonly stage: Stage,
    private readonly audio: HTMLElement,
    private readonly state: () => RoomState | null,
  ) {
    const refresh = () => this.refresh();
    room
      .on(RoomEvent.TrackSubscribed, (track: RemoteTrack) => {
        if (track.kind === Track.Kind.Audio) this.audio.append(track.attach());
        refresh();
      })
      .on(RoomEvent.TrackUnsubscribed, (track: RemoteTrack) => {
        track.detach().forEach((el) => el.remove());
        refresh();
      })
      .on(RoomEvent.TrackMuted, refresh)
      .on(RoomEvent.TrackUnmuted, refresh)
      .on(RoomEvent.ActiveSpeakersChanged, refresh)
      .on(RoomEvent.ParticipantDisconnected, refresh);
  }

  refresh(): void {
    const state = this.state();
    const people = [...this.room.remoteParticipants.values()];
    const role = (p: Participant) => state?.participants.get(p.identity)?.role;
    const video = (p: Participant, source: Track.Source) => {
      const pub = p.getTrackPublication(source);
      return pub?.track && !pub.isMuted ? pub.track : null;
    };

    const cameras = people.filter((p) => video(p, Track.Source.Camera));
    const rank: Partial<Record<string, number>> = { host: 0, cohost: 1, presenter: 2 };
    const byRank = (p: Participant) => rank[role(p) ?? ''] ?? 3;
    const speaking = new Set(this.room.activeSpeakers.map((p) => p.identity));
    // The host (or a presenter) if their camera is on; otherwise whoever is talking.
    const speaker =
      [...cameras].sort((a, b) => byRank(a) - byRank(b)).find((p) => byRank(p) < 3) ??
      cameras.find((p) => speaking.has(p.identity)) ??
      cameras[0];
    const sharer = [...people]
      .filter((p) => video(p, Track.Source.ScreenShare))
      .sort((a, b) => byRank(a) - byRank(b))[0];

    this.show('speaker', speaker ? [video(speaker, Track.Source.Camera)!] : []);
    this.show('screen', sharer ? [video(sharer, Track.Source.ScreenShare)!] : []);
    this.show(
      'gallery',
      cameras.slice(0, GALLERY_MAX).map((p) => video(p, Track.Source.Camera)!),
    );
  }

  private show(kind: 'speaker' | 'screen' | 'gallery', tracks: Track[]): void {
    const pod = this.stage.pod(kind);
    const box = pod?.querySelector<HTMLElement>('.pod__media');
    if (!pod || !box) return;
    const wanted = tracks.map((t) => {
      const key = `${kind}:${t.sid}`;
      let el = this.elements.get(key);
      if (!el) {
        el = t.attach();
        el.muted = true; // audio is played once, from the audio container
        this.elements.set(key, el);
      }
      return el;
    });
    for (const [key, el] of this.elements) {
      if (key.startsWith(`${kind}:`) && !wanted.includes(el)) {
        el.remove();
        this.elements.delete(key);
      }
    }
    box.replaceChildren(...wanted);
    box.dataset.count = String(wanted.length);
    this.stage.setEmpty(kind, wanted.length === 0);
  }
}
