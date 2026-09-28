import { createParamDecorator, type ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';

/**
 * Who is making this request, and from which device.
 *
 * Both are needed almost everywhere: a user alone is not enough to authorise playback, because
 * content keys are wrapped per device and the concurrent-stream limit is per device.
 */
export interface AuthContext {
  userId: string;
  deviceId: string;
  role: 'student' | 'teacher' | 'admin';
  revocationEpoch: number;
}

export const CurrentUser = createParamDecorator((_data: unknown, ctx: ExecutionContext) => {
  const request = ctx.switchToHttp().getRequest<Request & { auth?: AuthContext }>();
  return request.auth;
});
