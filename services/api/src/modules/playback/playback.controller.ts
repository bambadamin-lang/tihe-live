import { Body, Controller, Delete, HttpCode, Param, Post, Req } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { heartbeatBodySchema, startPlaybackBodySchema } from '@tihe/contracts';
import type { Request } from 'express';

import { AppError } from '../../common/app-error.js';
import { CurrentUser, type AuthContext } from '../auth/current-user.decorator.js';
import { PlaybackService } from './playback.service.js';

@ApiTags('playback')
@Controller('playback')
export class PlaybackController {
  constructor(private readonly playback: PlaybackService) {}

  @Post(':videoId/session')
  @ApiOperation({
    summary: 'Start a protected playback session',
    description:
      'Checks enrollment, licence validity, device binding and the concurrent-stream limit, then ' +
      'returns a manifest URL, the content key wrapped for this device alone, and watermark ' +
      'parameters. The wrapped key is useless on any other device and useless to Dart code on ' +
      'this one — only secure-core can open it.',
  })
  async start(
    @CurrentUser() auth: AuthContext,
    @Param('videoId') videoId: string,
    @Body() body: unknown,
    @Req() req: Request,
  ) {
    const parsed = startPlaybackBodySchema.parse(body);

    // The device in the token is authoritative. Accepting a body-supplied device id would let a
    // client mint a key wrapped for a device it does not control.
    if (parsed.deviceId !== auth.deviceId) {
      throw AppError.forbidden('deviceId must match the authenticated device');
    }

    return this.playback.start(auth.userId, auth.deviceId, videoId, parsed, req.ip);
  }

  @Post('sessions/:id/heartbeat')
  @ApiOperation({
    summary: 'Keep a session alive and check for revocation',
    description:
      'Returns the current revocationEpoch and a stop flag. This is what bounds revocation latency ' +
      'to one heartbeat interval: the server cannot push to a device, so the device asks.',
  })
  async heartbeat(
    @CurrentUser() auth: AuthContext,
    @Param('id') sessionId: string,
    @Body() body: unknown,
  ) {
    const parsed = heartbeatBodySchema.parse(body);
    return this.playback.heartbeat(auth.userId, auth.deviceId, sessionId, parsed.positionMs);
  }

  @Delete('sessions/:id')
  @HttpCode(204)
  @ApiOperation({
    summary: 'End a session',
    description: 'Frees the concurrent-stream slot; the client zeroes its copy of the key.',
  })
  async end(@CurrentUser() auth: AuthContext, @Param('id') sessionId: string) {
    await this.playback.end(auth.userId, sessionId);
  }
}
