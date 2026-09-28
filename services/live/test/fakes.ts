import type { MediaKind, MediaTrackSource } from '../src/core/capabilities.js';
import type { LiveKitPort, LiveKitWebhook } from '../src/livekit/livekit.port.js';
import type { ObjectStore } from '../src/storage/object-store.js';

/** Records every call, in one timeline shared with the object store, so tests can assert order. */
export class FakeLiveKit implements LiveKitPort {
  readonly tokens: {
    room: string;
    identity: string;
    sources: MediaTrackSource[];
    metadata: string;
  }[] = [];
  readonly rooms = new Set<string>();
  readonly permissions: { identity: string; sources: MediaTrackSource[] }[] = [];
  readonly mutes: { identity: string; media: MediaKind[] }[] = [];
  readonly removed: string[] = [];
  readonly recordings: { room: string; filepath: string; templateUrl: string }[] = [];

  constructor(readonly timeline: string[]) {}

  async mintToken(opts: {
    room: string;
    identity: string;
    name: string;
    sources: MediaTrackSource[];
    metadata: string;
  }) {
    this.tokens.push(opts);
    return `lk-token-for-${opts.identity}`;
  }
  async createRoom(opts: { name: string }) {
    this.rooms.add(opts.name);
    this.timeline.push(`livekit.createRoom ${opts.name}`);
  }
  async deleteRoom(name: string) {
    this.rooms.delete(name);
    this.timeline.push(`livekit.deleteRoom ${name}`);
  }
  async setPublishSources(_room: string, identity: string, sources: MediaTrackSource[]) {
    this.permissions.push({ identity, sources });
  }
  async muteTracks(_room: string, identity: string, media: MediaKind[]) {
    this.mutes.push({ identity, media });
  }
  async removeParticipant(_room: string, identity: string) {
    this.removed.push(identity);
  }
  async startRecording(opts: { room: string; filepath: string; templateUrl: string }) {
    this.recordings.push(opts);
    this.timeline.push(`livekit.startRecording ${opts.filepath}`);
    return 'EG_fake0001';
  }
  async stopRecording(egressId: string) {
    this.timeline.push(`livekit.stopRecording ${egressId}`);
  }
  async receiveWebhook(
    body: string,
    authorization: string | undefined,
  ): Promise<LiveKitWebhook | null> {
    if (authorization !== 'valid') return null;
    return JSON.parse(body) as LiveKitWebhook;
  }
}

export class TracingObjectStore implements ObjectStore {
  readonly objects = new Map<string, unknown>();
  constructor(readonly timeline: string[]) {}
  async putJson(key: string, value: unknown) {
    this.objects.set(key, structuredClone(value));
    this.timeline.push(
      `s3.put ${key} ${(value as { actualEndAt?: string | null }).actualEndAt ? 'final' : 'initial'}`,
    );
  }
}
