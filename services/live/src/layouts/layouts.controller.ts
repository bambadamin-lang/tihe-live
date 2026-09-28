import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Inject,
  Param,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { id, layoutProblems, saveLayoutBodySchema, type SavedLayout } from '@tihe/contracts';
import { AuthGuard, type AuthedRequest } from '../auth/auth.guard.js';
import { CLOCK, type Clock } from '../classroom/classroom-hub.js';
import { newId } from '../core/ids.js';
import { LiveHttpError, parseOrThrow } from '../http/errors.js';
import {
  LIVE_REPOSITORY,
  type LayoutRecord,
  type LiveRepository,
} from '../persistence/live-repository.js';

/** Maximum saved layouts per teacher; the editor is for a handful of favourites. */
const MAX_SAVED_LAYOUTS = 30;

const toDto = (r: LayoutRecord): SavedLayout => ({
  id: r.id,
  name: r.name,
  pods: r.pods,
  createdAt: r.createdAt.toISOString(),
});

/** A teacher's own saved custom layouts. Presets are in @tihe/contracts, not here. */
@Controller('layouts')
@UseGuards(AuthGuard)
export class LayoutsController {
  constructor(
    @Inject(LIVE_REPOSITORY) private readonly repo: LiveRepository,
    @Inject(CLOCK) private readonly clock: Clock,
  ) {}

  @Get()
  async list(@Req() req: AuthedRequest): Promise<SavedLayout[]> {
    return (await this.repo.listLayouts(req.caller.userId)).map(toDto);
  }

  @Post()
  async save(@Req() req: AuthedRequest, @Body() body: unknown): Promise<SavedLayout> {
    if (req.caller.accountRole === 'student') throw new LiveHttpError('FORBIDDEN', 'teachers only');
    const input = parseOrThrow(saveLayoutBodySchema, body);
    const problems = layoutProblems(input.pods);
    if (problems.length > 0)
      throw new LiveHttpError('VALIDATION_FAILED', 'invalid layout', { problems });
    if ((await this.repo.listLayouts(req.caller.userId)).length >= MAX_SAVED_LAYOUTS) {
      throw new LiveHttpError('VALIDATION_FAILED', 'too many saved layouts');
    }
    return toDto(
      await this.repo.saveLayout({
        id: newId('layout'),
        ownerId: req.caller.userId,
        name: input.name,
        pods: input.pods,
        createdAt: this.clock(),
      }),
    );
  }

  @Delete(':id')
  @HttpCode(204)
  async remove(@Req() req: AuthedRequest, @Param('id') raw: string): Promise<void> {
    const deleted = await this.repo.deleteLayout(
      parseOrThrow(id('layout'), raw),
      req.caller.userId,
    );
    if (!deleted) throw new LiveHttpError('NOT_FOUND', 'no such layout');
  }
}
