import type { MediaKind, MediaTrackSource } from '../core/capabilities.js';

/**
 * Everything services/live asks of LiveKit. An interface so the gateway and session logic are
 * tested against a fake, and so nothing outside livekit/ imports the SDK.
 */
export interface LiveKitPort {
  /** The join token: identity is the user id, so one account is one seat. */
  mintToken(opts: {
    room: string;
    identity: string;
    name: string;
    sources: MediaTrackSource[];
    /** Public per-participant metadata. Never put a phone number here — everyone can read it. */
    metadata: string;
  }): Promise<string>;

  createRoom(opts: { name: string; maxParticipants: number; metadata: string }): Promise<void>;
  deleteRoom(name: string): Promise<void>;

  /** Replace a participant's publish rights; the SFU enforces them. */
  setPublishSources(room: string, identity: string, sources: MediaTrackSource[]): Promise<void>;
  /** Mute the participant's published tracks of these kinds. */
  muteTracks(room: string, identity: string, media: MediaKind[]): Promise<void>;
  removeParticipant(room: string, identity: string): Promise<void>;

  /** Room composite rendered by our template, written to `filepath` in the raw bucket. */
  startRecording(opts: { room: string; filepath: string; templateUrl: string }): Promise<string>;
  stopRecording(egressId: string): Promise<void>;

  /** Verify and decode a webhook. Returns null when the signature is wrong. */
  receiveWebhook(body: string, authorization: string | undefined): Promise<LiveKitWebhook | null>;
}
export const LIVEKIT_PORT = Symbol('LIVEKIT_PORT');

/** The fields of a LiveKit webhook this service acts on. */
export interface LiveKitWebhook {
  event: string;
  roomName: string | null;
  egress: { egressId: string; status: string; error: string | null } | null;
}
