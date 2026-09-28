import { Controller, Headers, HttpCode, Inject, Logger, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { LIVEKIT_PORT, type LiveKitPort } from '../livekit/livekit.port.js';
import { LIVE_REPOSITORY, type LiveRepository } from '../persistence/live-repository.js';
import { RecordingService } from '../recording/recording.service.js';
import { SessionsService } from '../sessions/sessions.service.js';

const FAILED_EGRESS = new Set(['EGRESS_FAILED', 'EGRESS_ABORTED', 'EGRESS_LIMIT_REACHED']);

/**
 * LiveKit → services/live. services/api receives the same webhooks for the pipeline; here they
 * only keep the classroom honest: a failed recording is surfaced, an abandoned room is ended.
 * Always 200, even for events we ignore, or LiveKit retries forever (docs/06).
 */
@Controller('webhooks')
export class WebhooksController {
  private readonly logger = new Logger('WebhooksController');

  constructor(
    @Inject(LIVEKIT_PORT) private readonly livekit: LiveKitPort,
    @Inject(LIVE_REPOSITORY) private readonly repo: LiveRepository,
    private readonly sessions: SessionsService,
    private readonly recording: RecordingService,
  ) {}

  @Post('livekit')
  @HttpCode(200)
  async livekitWebhook(
    @Req() req: Request,
    @Headers('authorization') authorization: string | undefined,
  ): Promise<{ ok: true }> {
    const body = typeof req.body === 'string' ? req.body : '';
    const hook = await this.livekit.receiveWebhook(body, authorization);
    if (!hook) {
      this.logger.warn('rejected a LiveKit webhook with a bad signature');
      return { ok: true };
    }
    const session = hook.roomName ? await this.repo.findSession(hook.roomName) : null;
    if (!session) return { ok: true };

    if (hook.event === 'egress_ended' && hook.egress && FAILED_EGRESS.has(hook.egress.status)) {
      await this.recording.failed(session, hook.egress.error ?? hook.egress.status);
    } else if (hook.event === 'room_finished') {
      await this.sessions.endAbandoned(session.id);
    }
    return { ok: true };
  }
}
