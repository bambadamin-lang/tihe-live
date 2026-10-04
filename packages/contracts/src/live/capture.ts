import { z } from 'zod';

/**
 * Screen-capture protection for the live classroom. See ADR-0011 and
 * docs/11-live-classroom.md §8.
 */

/** The facts a client can observe. Native code reports these; Dart decides what they mean. */
export const CAPTURE_SIGNALS = [
  /** The OS says this app is being recorded (Android 15 callback, iOS capture state). */
  'os_recording',
  /** A screenshot was taken. An instant event, not a state. */
  'screenshot',
  /** A known screen-recorder process is running (Windows, macOS). */
  'recorder_process',
  /** The screen is mirrored or sent to an external display (AirPlay, Miracast). */
  'external_display',
  /** The app runs inside a Remote Desktop session, which can itself be recorded. */
  'remote_session',
  /** The OS refused the capture block (e.g. SetWindowDisplayAffinity failed). */
  'block_failed',
  /**
   * The recording outlasted `recordingGraceSeconds`, so the app took the participant out of
   * the class. An instant, sent as the client leaves; they may rejoin once the recorder is closed.
   */
  'removed_for_recording',
] as const;
export const captureSignalSchema = z.enum(CAPTURE_SIGNALS);
export type CaptureSignal = z.infer<typeof captureSignalSchema>;

/**
 * Sent in the join response, so the institute can tune protection without an app release.
 * `block: false` only when the course sets `allowCapture` (accessibility, remote support).
 */
export const capturePolicySchema = z.object({
  block: z.boolean(),
  /**
   * Windows affinity. `monitor`: captures show a black box — used for students, so the
   * censorship is visible. `exclude`: the window vanishes from captures — used for presenters,
   * so their own screen share does not contain a black hole.
   */
  windowsAffinity: z.enum(['monitor', 'exclude']),
  /** Pixel blocking never covers audio, so censoring also mutes the class. */
  censorAudio: z.boolean(),
  /** Tell the host when this participant is detected capturing. */
  reportToHost: z.boolean(),
  /** Lower-case executable / app names. Matched exactly, never as substrings. */
  recorderProcesses: z.object({
    windows: z.array(z.string().min(1).max(64)).max(200),
    macos: z.array(z.string().min(1).max(64)).max(200),
  }),
  /** Render the iOS classroom inside a secure layer. A flag because it relies on private UIKit structure. */
  iosSecureLayer: z.boolean(),
  /** How often desktop clients rescan processes. */
  scanIntervalMs: z.number().int().min(1000).max(60000),
  /**
   * Censoring is immediate; a recording still running this long after takes the participant
   * out of the class (ADR-0011, amended). Null when capture is allowed for the course.
   */
  recordingGraceSeconds: z.number().int().min(3).max(120).nullable(),
});
export type CapturePolicy = z.infer<typeof capturePolicySchema>;

export const DEFAULT_RECORDER_PROCESSES: CapturePolicy['recorderProcesses'] = {
  windows: [
    'obs64.exe',
    'obs32.exe',
    'obs.exe',
    'streamlabs obs.exe',
    'bdcam.exe',
    'camtasiastudio.exe',
    'camrecorder.exe',
    'sharex.exe',
    'snagit32.exe',
    'snagiteditor.exe',
    'fraps.exe',
    'action.exe',
    'dxtory.exe',
    'apowerrec.exe',
    'screenrec.exe',
    'fbrecorder.exe',
    'loom.exe',
    'xsplit.core.exe',
    'icecreamscreenrecorder.exe',
    'ffmpeg.exe',
  ],
  macos: [
    'obs',
    'screencaptureui',
    'loom',
    'cleanshot x',
    'camtasia',
    'screenflow',
    'kap',
    'snagit',
    'capto',
    'screen studio',
    'ffmpeg',
  ],
};
