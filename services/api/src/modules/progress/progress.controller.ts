import { Body, Controller, Get, Param, Post, Put } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { updateProgressBodySchema, watchEventsBodySchema } from '@tihe/contracts';

import { CurrentUser, type AuthContext } from '../auth/current-user.decorator.js';
import { ProgressService } from './progress.service.js';

@ApiTags('progress')
@Controller('progress')
export class ProgressController {
  constructor(private readonly progress: ProgressService) {}

  @Get(':videoId')
  @ApiOperation({ summary: 'Resume point for a video' })
  async get(@CurrentUser() auth: AuthContext, @Param('videoId') videoId: string) {
    return this.progress.get(auth.userId, videoId);
  }

  @Put(':videoId')
  @ApiOperation({
    summary: 'Update the resume point',
    description:
      'The position only moves forward unless completed is set, so out-of-order heartbeats from a ' +
      "flaky connection cannot rewind a student's progress.",
  })
  async set(
    @CurrentUser() auth: AuthContext,
    @Param('videoId') videoId: string,
    @Body() body: unknown,
  ) {
    const parsed = updateProgressBodySchema.parse(body);
    return this.progress.set(auth.userId, videoId, parsed.positionMs, parsed.completed);
  }

  @Post('events')
  @ApiOperation({
    summary: 'Submit watch events, including an offline backlog',
    description:
      'Accepts client timestamps so offline viewing keeps its real timing, clamped against ' +
      'far-future values. Returns the current revocationEpoch, so a device that was offline when ' +
      'its licence was revoked learns about it here.',
  })
  async events(@CurrentUser() auth: AuthContext, @Body() body: unknown) {
    const parsed = watchEventsBodySchema.parse(body);
    return this.progress.recordEvents(auth.userId, auth.deviceId, parsed.events);
  }
}
