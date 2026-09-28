import {
  AccessToken,
  EgressClient,
  EgressStatus,
  EncodedFileOutput,
  EncodingOptionsPreset,
  RoomServiceClient,
  TrackSource,
  WebhookReceiver,
} from 'livekit-server-sdk';
import type { MediaKind, MediaTrackSource } from '../core/capabilities.js';
import type { LiveKitPort, LiveKitWebhook } from './livekit.port.js';

const SOURCE: Record<MediaTrackSource, TrackSource> = {
  microphone: TrackSource.MICROPHONE,
  camera: TrackSource.CAMERA,
  screen_share: TrackSource.SCREEN_SHARE,
  screen_share_audio: TrackSource.SCREEN_SHARE_AUDIO,
};

const MEDIA_SOURCES: Record<MediaKind, TrackSource[]> = {
  audio: [TrackSource.MICROPHONE],
  video: [TrackSource.CAMERA],
  screen: [TrackSource.SCREEN_SHARE, TrackSource.SCREEN_SHARE_AUDIO],
};

/** Rooms outlive a brief host disconnect, but not an abandoned class. */
const EMPTY_TIMEOUT_SECONDS = 600;
const DEPARTURE_TIMEOUT_SECONDS = 120;
/** Join tokens only need to connect; LiveKit refreshes them for the rest of the session. */
const TOKEN_TTL = '10m';

const isNotFound = (err: unknown) =>
  err instanceof Error && /not.?found|does not exist|404/i.test(err.message);

export class LiveKitAdapter implements LiveKitPort {
  private readonly rooms: RoomServiceClient;
  private readonly egress: EgressClient;
  private readonly webhooks: WebhookReceiver;

  constructor(
    apiUrl: string,
    private readonly apiKey: string,
    private readonly apiSecret: string,
    private readonly allowUnsignedWebhooks: boolean,
  ) {
    this.rooms = new RoomServiceClient(apiUrl, apiKey, apiSecret);
    this.egress = new EgressClient(apiUrl, apiKey, apiSecret);
    this.webhooks = new WebhookReceiver(apiKey, apiSecret);
  }

  async mintToken(opts: {
    room: string;
    identity: string;
    name: string;
    sources: MediaTrackSource[];
    metadata: string;
  }): Promise<string> {
    const token = new AccessToken(this.apiKey, this.apiSecret, {
      identity: opts.identity,
      name: opts.name,
      metadata: opts.metadata,
      ttl: TOKEN_TTL,
    });
    token.addGrant({
      roomJoin: true,
      room: opts.room,
      canSubscribe: true,
      canPublish: opts.sources.length > 0,
      canPublishSources: opts.sources.map((s) => SOURCE[s]),
      // Classroom state travels over the gateway (ADR-0010); data channels stay shut so nobody
      // can forge whiteboard or permission messages peer to peer.
      canPublishData: false,
      canUpdateOwnMetadata: false,
    });
    return token.toJwt();
  }

  async createRoom(opts: {
    name: string;
    maxParticipants: number;
    metadata: string;
  }): Promise<void> {
    await this.rooms.createRoom({
      name: opts.name,
      maxParticipants: opts.maxParticipants,
      emptyTimeout: EMPTY_TIMEOUT_SECONDS,
      departureTimeout: DEPARTURE_TIMEOUT_SECONDS,
      metadata: opts.metadata,
    });
  }

  async deleteRoom(name: string): Promise<void> {
    try {
      await this.rooms.deleteRoom(name);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async setPublishSources(
    room: string,
    identity: string,
    sources: MediaTrackSource[],
  ): Promise<void> {
    try {
      await this.rooms.updateParticipant(room, identity, {
        permission: {
          canSubscribe: true,
          canPublish: sources.length > 0,
          canPublishSources: sources.map((s) => SOURCE[s]),
          canPublishData: false,
          canUpdateMetadata: false,
        },
      });
    } catch (err) {
      // Not connected to the SFU right now: their next join token carries the new rights.
      if (!isNotFound(err)) throw err;
    }
  }

  async muteTracks(room: string, identity: string, media: MediaKind[]): Promise<void> {
    const wanted = new Set(media.flatMap((m) => MEDIA_SOURCES[m]));
    let tracks;
    try {
      tracks = (await this.rooms.getParticipant(room, identity)).tracks;
    } catch (err) {
      if (isNotFound(err)) return;
      throw err;
    }
    await Promise.all(
      tracks
        .filter((t) => wanted.has(t.source) && !t.muted)
        .map((t) => this.rooms.mutePublishedTrack(room, identity, t.sid, true)),
    );
  }

  async removeParticipant(room: string, identity: string): Promise<void> {
    try {
      await this.rooms.removeParticipant(room, identity);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async startRecording(opts: {
    room: string;
    filepath: string;
    templateUrl: string;
  }): Promise<string> {
    // The S3 destination (tihe-raw) comes from egress.yaml, so no storage credential is sent
    // with each request.
    const info = await this.egress.startRoomCompositeEgress(
      opts.room,
      new EncodedFileOutput({ filepath: opts.filepath }),
      { customBaseUrl: opts.templateUrl, encodingOptions: EncodingOptionsPreset.H264_1080P_30 },
    );
    return info.egressId;
  }

  async stopRecording(egressId: string): Promise<void> {
    try {
      await this.egress.stopEgress(egressId);
    } catch (err) {
      if (!isNotFound(err) && !/not active|already|complete/i.test(String(err))) throw err;
    }
  }

  async receiveWebhook(
    body: string,
    authorization: string | undefined,
  ): Promise<LiveKitWebhook | null> {
    let event;
    try {
      event = await this.webhooks.receive(body, authorization, this.allowUnsignedWebhooks);
    } catch {
      return null;
    }
    const info = event.egressInfo;
    return {
      event: event.event,
      roomName: event.room?.name ?? info?.roomName ?? null,
      egress: info
        ? {
            egressId: info.egressId,
            status: EgressStatus[info.status] ?? String(info.status),
            error: info.error || null,
          }
        : null,
    };
  }
}
