import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import {
  createClassBodySchema,
  id,
  listClassesQuerySchema,
  updateClassBodySchema,
  type LiveClass,
  type LiveSession,
} from '@tihe/contracts';
import { AuthGuard, type AuthedRequest } from '../auth/auth.guard.js';
import { parseOrThrow } from '../http/errors.js';
import { SessionsService } from '../sessions/sessions.service.js';
import { ClassesService } from './classes.service.js';

@Controller('classes')
@UseGuards(AuthGuard)
export class ClassesController {
  constructor(
    private readonly classes: ClassesService,
    private readonly sessions: SessionsService,
  ) {}

  @Post()
  create(@Req() req: AuthedRequest, @Body() body: unknown): Promise<LiveClass> {
    return this.classes.create(req.caller, parseOrThrow(createClassBodySchema, body));
  }

  @Get()
  list(@Req() req: AuthedRequest, @Query() query: unknown): Promise<LiveClass[]> {
    return this.classes.list(req.caller, parseOrThrow(listClassesQuerySchema, query).courseId);
  }

  @Get(':id')
  get(@Req() req: AuthedRequest, @Param('id') classId: string): Promise<LiveClass> {
    return this.classes.get(req.caller, parseOrThrow(id('liveClass'), classId));
  }

  @Patch(':id')
  update(
    @Req() req: AuthedRequest,
    @Param('id') classId: string,
    @Body() body: unknown,
  ): Promise<LiveClass> {
    return this.classes.update(
      req.caller,
      parseOrThrow(id('liveClass'), classId),
      parseOrThrow(updateClassBodySchema, body),
    );
  }

  /** Start the class now. Returns the live session (the existing one if already started). */
  @Post(':id/sessions')
  start(@Req() req: AuthedRequest, @Param('id') classId: string): Promise<LiveSession> {
    return this.sessions.start(req.caller, parseOrThrow(id('liveClass'), classId));
  }
}
