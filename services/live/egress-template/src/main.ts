import EgressHelper from '@livekit/egress-sdk';
import { Room } from 'livekit-client';
import type { RoomState } from '../../src/core/room-state.js';
import { runDemo } from './demo.js';
import { ClassroomFeed } from './feed.js';
import { loadFonts } from './fonts.js';
import { MediaBinder } from './media.js';
import { Stage } from './stage.js';
import './styles.css';

/**
 * Entry point. Egress opens this page with `url` and `token` (its LiveKit credentials); we add
 * `session` and `gateway` (services/live/src/recording). `?demo` renders a fixture instead,
 * for screenshots and development without LiveKit.
 */
/** Start recording even if the gateway is slow: a class without a board beats no recording. */
const START_DEADLINE_MS = 8000;

const params = new URLSearchParams(location.search);
const root = document.getElementById('stage')!;
const audio = document.getElementById('audio')!;

void loadFonts().then(() => (params.has('demo') ? runDemo(root, params) : runLive()));

async function runLive(): Promise<void> {
  const stage = new Stage(root);
  let state: RoomState | null = null;
  let boardDirty = true;
  let started = false;
  const start = () => {
    if (started) return;
    started = true;
    EgressHelper.startRecording();
  };

  const room = new Room({ adaptiveStream: false, dynacast: false });
  const media = new MediaBinder(room, stage, audio, () => state);

  const feed = new ClassroomFeed(
    params.get('gateway') ?? '',
    EgressHelper.getAccessToken(),
    (what) => {
      state = feed.state;
      if (!state) return;
      if (what === 'ended') {
        EgressHelper.endRecording();
        return;
      }
      // The stage's layout and title change only with the room's state; a board event or a
      // preview (25 a second per person drawing) needs only the board drawn again.
      if (what === 'state') {
        stage.render(state);
        media.refresh();
      }
      boardDirty = true;
      start();
    },
  );
  feed.connect();

  await room.connect(EgressHelper.getLiveKitURL(), EgressHelper.getAccessToken(), {
    autoSubscribe: true,
  });
  EgressHelper.setRoom(room);
  media.refresh();
  setTimeout(start, START_DEADLINE_MS);

  const frame = () => {
    const now = Date.now();
    const swept = feed.sweep(now);
    const lasers = [...feed.previews.values()].some((p) => p.tool === 'laser');
    if (state && (boardDirty || swept || lasers)) {
      const page = state.board.pages.find((p) => p.id === state!.board.activePageId);
      stage.drawBoard(page, state, feed.previews.values(), now);
      boardDirty = false;
    }
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}
