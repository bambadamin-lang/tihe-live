import { Controller, Headers, Logger, Post, Req } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiExcludeEndpoint, ApiOperation, ApiTags } from '@nestjs/swagger';
import { livekitWebhookSchema, recordingMetadataSchema } from '@tihe/contracts';
import type { Request } from 'express';

import { newId } from '../../common/ids.js';
import { PrismaService } from '../../common/prisma.service.js';
import type { Env } from '../../config/configuration.js';
import { Public } from '../auth/auth.guard.js';
import { StorageService } from '../storage/storage.service.js';
import { verifyLivekitWebhook } from './livekit.verifier.js';

/**
 * The entry point for the recording pipeline. Contract: docs/06-recording-pipeline.md.
 *
 * Two behaviours worth knowing before changing anything here:
 *
 * * **Always 200 for anything we recognise as a LiveKit delivery.** A non-2xx makes LiveKit retry
 *   forever, so an event we do not handle is logged and acknowledged, not rejected.
 * * **Idempotent on egressId.** LiveKit redelivers, and a duplicate must not create a second
 *   recording row or a second processing job.
 */
@ApiTags('webhooks')
@Controller('webhooks')
export class WebhooksController {
  private readonly logger = new Logger('LiveKitWebhook');

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService<Env, true>,
    private readonly storage: StorageService,
  ) {}

  @Public()
  @Post('livekit')
  @ApiExcludeEndpoint()
  @ApiOperation({ summary: 'LiveKit egress webhook' })
  async livekit(
    @Req() req: Request & { rawBody?: Buffer },
    @Headers('authorization') authorization?: string,
  ) {
    const rawBody = req.rawBody ?? Buffer.from(JSON.stringify(req.body ?? {}));

    const verification = verifyLivekitWebhook(
      authorization,
      rawBody,
      this.config.getOrThrow('LIVEKIT_API_KEY', { infer: true }),
      this.config.getOrThrow('LIVEKIT_API_SECRET', { infer: true }),
      { allowUnsigned: this.config.getOrThrow('LIVEKIT_WEBHOOK_ALLOW_UNSIGNED', { infer: true }) },
    );

    if (!verification.valid) {
      // 401 here, not 200: an unverifiable request is not a LiveKit delivery, and it should not be
      // silently accepted. A forged egress_ended would publish arbitrary video into a real course.
      this.logger.warn(`rejected webhook: ${verification.reason}`);
      return { accepted: false, reason: 'unverified' };
    }

    const parsed = livekitWebhookSchema.safeParse(verification.payload);
    if (!parsed.success) {
      this.logger.warn('webhook payload did not match the expected shape; ignoring');
      return { accepted: false, reason: 'unrecognised payload' };
    }

    const event = parsed.data;

    if (event.event !== 'egress_ended') {
      // egress_started, room_finished and friends are informational. Acknowledge so LiveKit stops.
      this.logger.debug(`ignoring event: ${event.event}`);
      return { accepted: true, handled: false };
    }

    const info = event.egressInfo;
    if (!info) {
      this.logger.warn('egress_ended with no egressInfo; ignoring');
      return { accepted: true, handled: false };
    }

    const existing = await this.prisma.recording.findUnique({ where: { egressId: info.egressId } });
    if (existing) {
      this.logger.debug(`duplicate delivery for egress ${info.egressId}; already recorded`);
      return { accepted: true, handled: true, recordingId: existing.id, duplicate: true };
    }

    const file = info.fileResults[0];
    const failed = info.status !== 'EGRESS_COMPLETE' || !file;

    // Derive the class and session from the storage prefix that services/live wrote to.
    const prefixMatch = file?.filename?.match(/recordings\/([^/]+)\/([^/]+)\//);
    const classId = prefixMatch?.[1] ?? info.roomName;
    const sessionId = prefixMatch?.[2] ?? info.egressId;

    // metadata.json carries the courseId, which decides who may see the resulting video. Without it
    // the recording is parked for manual filing rather than risk publishing to the wrong audience.
    const metadata = file
      ? await this.storage.readJson<unknown>(
          this.storage.rawBucket,
          `recordings/${classId}/${sessionId}/metadata.json`,
        )
      : null;

    const parsedMetadata = metadata ? recordingMetadataSchema.safeParse(metadata) : null;
    const courseId = parsedMetadata?.success ? parsedMetadata.data.courseId : null;

    const status = failed
      ? ('failed' as const)
      : courseId
        ? ('pending' as const)
        : ('needs_attention' as const);

    const recording = await this.prisma.recording.create({
      data: {
        id: newId('recording'),
        classId,
        sessionId,
        courseId,
        egressId: info.egressId,
        rawStorageKey: file?.filename ?? null,
        status,
        error: failed ? (info.error ?? `egress status ${info.status}`) : null,
        metadata: metadata ? (metadata as object) : undefined,
        startedAt: info.startedAt ? new Date(info.startedAt / 1_000_000) : null,
        endedAt: info.endedAt ? new Date(info.endedAt / 1_000_000) : null,
      },
    });

    if (failed) {
      // A class that was not recorded needs a human to know. Silence would look identical to a
      // class nobody attended.
      this.logger.error(
        `egress ${info.egressId} did not complete (${info.status}); recording ${recording.id} marked failed`,
      );
    } else if (!courseId) {
      this.logger.warn(
        `recording ${recording.id} has no courseId in metadata.json; needs manual filing`,
      );
    } else {
      this.logger.log(
        `recording ${recording.id} queued for course ${courseId} (${file?.filename})`,
      );
      // M2: enqueue ingest:process on BullMQ here. Until the worker exists the row is the queue,
      // and ingest-worker will pick up `pending` rows.
    }

    return { accepted: true, handled: true, recordingId: recording.id, status };
  }
}
