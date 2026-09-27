import { serverMessageSchema, type ClassroomCommand, type ServerMessage } from '@tihe/contracts';
import { WebSocket } from 'ws';

/**
 * A classroom client for tests. Every message it receives is validated against the contract,
 * so a server that drifts from packages/contracts fails here, not in the Flutter app.
 */
export class TestClient {
  readonly messages: ServerMessage[] = [];
  closeCode: number | null = null;
  private counter = 0;
  private waiters: (() => void)[] = [];

  private constructor(private readonly ws: WebSocket) {
    ws.on('message', (data) => {
      this.messages.push(serverMessageSchema.parse(JSON.parse(data.toString())));
      this.wake();
    });
    ws.on('close', (code) => {
      this.closeCode = code;
      this.wake();
    });
  }

  static async connect(
    url: string,
    ticket: string,
    lastSeq: number | null = null,
  ): Promise<TestClient> {
    const ws = new WebSocket(url);
    await new Promise<void>((resolve, reject) => {
      ws.once('open', () => resolve());
      ws.once('error', reject);
    });
    const client = new TestClient(ws);
    ws.send(JSON.stringify({ t: 'hello', ticket, lastSeq }));
    await client.waitFor((m) => m.t === 'welcome' || m.t === 'bye');
    return client;
  }

  get welcome() {
    const w = this.messages.find((m) => m.t === 'welcome');
    if (!w || w.t !== 'welcome') throw new Error('no welcome');
    return w;
  }

  get lastSeq(): number {
    let seq = this.welcome.seq;
    for (const m of this.messages) if (m.t === 'evt') seq = Math.max(seq, m.seq);
    return seq;
  }

  events() {
    return this.messages.flatMap((m) => (m.t === 'evt' ? [m.evt] : []));
  }

  /** Sends a command and resolves with its ack or nack. */
  async command(cmd: ClassroomCommand): Promise<ServerMessage> {
    const id = `c${++this.counter}`;
    this.ws.send(JSON.stringify({ t: 'cmd', id, cmd }));
    return this.waitFor((m) => (m.t === 'ack' || m.t === 'nack') && m.id === id);
  }

  sendRaw(value: unknown): void {
    this.ws.send(JSON.stringify(value));
  }

  async waitFor(match: (m: ServerMessage) => boolean, timeoutMs = 2000): Promise<ServerMessage> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const found = this.messages.find(match);
      if (found) return found;
      if (this.closeCode !== null)
        throw new Error(`socket closed (${this.closeCode}) while waiting`);
      const left = deadline - Date.now();
      if (left <= 0) throw new Error('timed out waiting for message');
      await new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, left);
        this.waiters.push(() => {
          clearTimeout(timer);
          resolve();
        });
      });
    }
  }

  async waitForClose(timeoutMs = 2000): Promise<number> {
    const deadline = Date.now() + timeoutMs;
    while (this.closeCode === null) {
      if (Date.now() > deadline) throw new Error('socket did not close');
      await new Promise((r) => setTimeout(r, 10));
    }
    return this.closeCode;
  }

  close(): void {
    this.ws.close();
  }

  private wake() {
    const waiters = this.waiters;
    this.waiters = [];
    for (const w of waiters) w();
  }
}
