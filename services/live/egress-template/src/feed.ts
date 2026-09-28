import { serverMessageSchema, type BoardProgress, type ServerMessage } from '@tihe/contracts';
import { applyEvent, roomStateFromSnapshot, type RoomState } from '../../src/core/room-state.js';
import type { Preview } from './board.js';

/**
 * The classroom as the recorder sees it: connects to the gateway with Egress's own LiveKit
 * token (the gateway accepts it for hidden recorders), then applies events with the server's
 * own `applyEvent`. Read-only — the recorder never sends a command.
 */
export class ClassroomFeed {
  state: RoomState | null = null;
  readonly previews = new Map<string, Preview>();
  private ws: WebSocket | null = null;
  private retry = 0;

  constructor(
    private readonly url: string,
    private readonly ticket: string,
    private readonly onChange: (what: 'state' | 'board' | 'ended') => void,
  ) {}

  connect(): void {
    const ws = new WebSocket(this.url);
    this.ws = ws;
    ws.onopen = () => {
      this.retry = 0;
      ws.send(
        JSON.stringify({ t: 'hello', ticket: this.ticket, lastSeq: this.state?.seq ?? null }),
      );
    };
    ws.onmessage = (e) => {
      const parsed = serverMessageSchema.safeParse(JSON.parse(String(e.data)));
      if (parsed.success) this.receive(parsed.data);
    };
    ws.onclose = (e) => {
      if (e.code >= 4000) return; // told to go: ended, or refused
      // Egress keeps recording through a gateway blip; the stage just freezes until we're back.
      setTimeout(() => this.connect(), Math.min(10_000, 500 * 2 ** this.retry++));
    };
  }

  receive(msg: ServerMessage): void {
    switch (msg.t) {
      case 'welcome':
        if (msg.snapshot) this.state = roomStateFromSnapshot(msg.snapshot, msg.seq);
        for (const e of msg.replay ?? []) if (this.state) applyEvent(this.state, e);
        return this.onChange('state');
      case 'evt': {
        if (!this.state || msg.seq <= this.state.seq) return;
        applyEvent(this.state, msg);
        if (msg.evt.type === 'wb.added') for (const i of msg.evt.items) this.previews.delete(i.id);
        if (msg.evt.type === 'class.ended') return this.onChange('ended');
        return this.onChange(msg.evt.type.startsWith('wb.') ? 'board' : 'state');
      }
      case 'eph':
        this.preview(msg.eph);
        return this.onChange('board');
      case 'bye':
        return this.onChange('ended');
      default:
        return;
    }
  }

  private preview(p: BoardProgress): void {
    const existing = this.previews.get(p.strokeId);
    const points = existing ? [...existing.points, ...p.points] : [...p.points];
    // A finished stroke's preview stays until its committed wb.add replaces it, so nothing flickers.
    this.previews.set(p.strokeId, {
      tool: p.tool,
      color: p.color,
      width: p.width,
      points,
      updatedAt: Date.now(),
    });
  }

  /** Drop previews whose author went quiet (a lost pen-up) and lasers that have faded. */
  sweep(now: number): boolean {
    let changed = false;
    for (const [id, p] of this.previews) {
      const limit = p.tool === 'laser' ? 1500 : 5000;
      if (now - p.updatedAt > limit) {
        this.previews.delete(id);
        changed = true;
      }
    }
    return changed;
  }

  close(): void {
    this.ws?.close();
  }
}
