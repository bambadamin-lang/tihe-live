import type { IncomingMessage, Server } from 'node:http';
import type { Duplex } from 'node:stream';
import { Inject, Injectable, Logger, type OnApplicationShutdown } from '@nestjs/common';
import {
  GATEWAY_CLOSE_CODES,
  clientMessageSchema,
  type ClientMessage,
  type ServerMessage,
} from '@tihe/contracts';
import { WebSocket, WebSocketServer, type RawData } from 'ws';
import { TicketService } from '../auth/tickets.js';
import { gatewayError } from '../core/room-reducer.js';
import { ClassroomHub } from './classroom-hub.js';
import type { Connection, RoomActor } from './room-actor.js';

export const GATEWAY_PATH = '/v1/live/ws';
/** A client must say hello this soon after connecting. */
const HELLO_TIMEOUT_MS = 5000;
/** Dead connections (a laptop lid closed) are found by ping within this long. */
const HEARTBEAT_MS = 20_000;
/** A 2000-point stroke is about 20 KB; this leaves room without inviting abuse. */
const MAX_MESSAGE_BYTES = 256 * 1024;
const MAX_PROTOCOL_ERRORS = 5;

/**
 * The classroom WebSocket (ADR-0010). Authenticates the first message with a gateway ticket,
 * hands the connection to its room, and turns room results into acks and nacks. All classroom
 * rules live in the room; this file is transport only.
 */
@Injectable()
export class ClassroomGateway implements OnApplicationShutdown {
  private readonly logger = new Logger('ClassroomGateway');
  private readonly wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES });
  private readonly alive = new WeakSet<WebSocket>();
  private heartbeat: NodeJS.Timeout | null = null;

  constructor(
    private readonly hub: ClassroomHub,
    @Inject(TicketService) private readonly tickets: TicketService,
  ) {}

  attach(server: Server): void {
    server.on('upgrade', (req: IncomingMessage, socket: Duplex, head: Buffer) => {
      const path = new URL(req.url ?? '/', 'http://localhost').pathname;
      if (path !== GATEWAY_PATH) {
        socket.destroy();
        return;
      }
      this.wss.handleUpgrade(req, socket, head, (ws) => this.onSocket(ws));
    });
    this.heartbeat = setInterval(() => {
      for (const ws of this.wss.clients) {
        if (!this.alive.has(ws)) {
          ws.terminate();
          continue;
        }
        this.alive.delete(ws);
        ws.ping();
      }
    }, HEARTBEAT_MS);
    this.heartbeat.unref();
  }

  onApplicationShutdown(): void {
    if (this.heartbeat) clearInterval(this.heartbeat);
    for (const ws of this.wss.clients) ws.close(1001);
    this.wss.close();
  }

  private onSocket(ws: WebSocket): void {
    this.alive.add(ws);
    ws.on('pong', () => this.alive.add(ws));

    let joined: { actor: RoomActor; conn: Connection } | null = null;
    let protocolErrors = 0;
    let queue: Promise<void> = Promise.resolve();
    const send = (msg: ServerMessage) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
    };
    const helloTimer = setTimeout(
      () => ws.close(GATEWAY_CLOSE_CODES.unauthenticated),
      HELLO_TIMEOUT_MS,
    );

    const protocolError = (id?: string) => {
      if (id)
        send({ t: 'nack', id, error: gatewayError('VALIDATION_FAILED', 'malformed message') });
      if (++protocolErrors > MAX_PROTOCOL_ERRORS) ws.close(GATEWAY_CLOSE_CODES.protocolError);
    };

    const handle = async (data: RawData, isBinary: boolean) => {
      if (isBinary) return protocolError();
      let raw: unknown;
      try {
        raw = JSON.parse(data.toString());
      } catch {
        return protocolError();
      }
      const parsed = clientMessageSchema.safeParse(raw);
      if (!parsed.success) {
        const id = (raw as { t?: unknown; id?: unknown } | null)?.id;
        return protocolError(typeof id === 'string' ? id : undefined);
      }
      const msg: ClientMessage = parsed.data;

      if (!joined) {
        if (msg.t !== 'hello') return void ws.close(GATEWAY_CLOSE_CODES.unauthenticated);
        clearTimeout(helloTimer);
        joined = await this.hello(ws, msg.ticket, msg.lastSeq, send);
        return;
      }

      const { actor, conn } = joined;
      switch (msg.t) {
        case 'hello':
          return protocolError();
        case 'ping':
          return send({ t: 'pong' });
        case 'cmd': {
          if (conn.role === 'recorder') {
            return send({
              t: 'nack',
              id: msg.id,
              error: gatewayError('FORBIDDEN', 'recorder is read-only'),
            });
          }
          const result = actor.submit({ kind: 'command', actorId: conn.userId, cmd: msg.cmd });
          return send(
            result.ok ? { t: 'ack', id: msg.id } : { t: 'nack', id: msg.id, error: result.error },
          );
        }
        case 'eph':
          if (conn.role !== 'recorder') actor.relay(conn, msg.eph);
          return;
      }
    };

    // Messages are handled strictly in order, even across the async ticket check.
    ws.on('message', (data, isBinary) => {
      queue = queue
        .then(() => handle(data, isBinary))
        .catch((err) => this.logger.error('gateway message failed', err));
    });
    ws.on('close', () => {
      clearTimeout(helloTimer);
      queue = queue.then(() => {
        if (joined) joined.actor.disconnect(joined.conn);
      });
    });
    ws.on('error', () => ws.terminate());
  }

  private async hello(
    ws: WebSocket,
    ticket: string,
    lastSeq: number | null,
    send: (msg: ServerMessage) => void,
  ): Promise<{ actor: RoomActor; conn: Connection } | null> {
    const identity = await this.tickets.verify(ticket);
    if (!identity) {
      send({ t: 'bye', error: gatewayError('UNAUTHENTICATED', 'invalid or expired ticket') });
      ws.close(GATEWAY_CLOSE_CODES.unauthenticated);
      return null;
    }
    const actor = await this.hub.find(identity.sessionId);
    if (!actor || actor.state.ended) {
      send({ t: 'bye', error: gatewayError('CLASS_ENDED', 'class is not live') });
      ws.close(GATEWAY_CLOSE_CODES.classEnded);
      return null;
    }
    const conn: Connection = {
      userId: identity.userId,
      role: identity.role,
      send,
      close: (code) => ws.close(code),
      bufferedAmount: () => ws.bufferedAmount,
    };
    const result = actor.connect(conn, identity.name, lastSeq);
    return result && !result.ok ? null : { actor, conn };
  }
}
