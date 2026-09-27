import { Controller, Get, HttpCode, Param, Post, Req, UseGuards } from '@nestjs/common';
import { id, type AttendanceEntry, type JoinResponse, type LiveSession } from '@tihe/contracts';
import { AuthGuard, type AuthedRequest } from '../auth/auth.guard.js';
import { parseOrThrow } from '../http/errors.js';
import { SessionsService } from './sessions.service.js';

const sessionId = (raw: string) => parseOrThrow(id('liveSession'), raw);

@Controller('sessions')
@UseGuards(AuthGuard)
export class SessionsController {
  constructor(private readonly sessions: SessionsService) {}

  @Get(':id')
  get(@Req() req: AuthedRequest, @Param('id') raw: string): Promise<LiveSession> {
    return this.sessions.get(req.caller, sessionId(raw));
  }

  @Post(':id/join')
  @HttpCode(200)
  join(@Req() req: AuthedRequest, @Param('id') raw: string): Promise<JoinResponse> {
    return this.sessions.join(req.caller, sessionId(raw));
  }

  @Post(':id/recording/start')
  @HttpCode(200)
  startRecording(@Req() req: AuthedRequest, @Param('id') raw: string): Promise<LiveSession> {
    return this.sessions.startRecording(req.caller, sessionId(raw));
  }

  @Post(':id/end')
  @HttpCode(200)
  end(@Req() req: AuthedRequest, @Param('id') raw: string): Promise<LiveSession> {
    return this.sessions.end(req.caller, sessionId(raw));
  }

  @Get(':id/attendance')
  attendance(@Req() req: AuthedRequest, @Param('id') raw: string): Promise<AttendanceEntry[]> {
    return this.sessions.attendance(req.caller, sessionId(raw));
  }
}
