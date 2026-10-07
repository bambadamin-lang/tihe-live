import { timingSafeEqual } from 'node:crypto';

import { type CanActivate, type ExecutionContext, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';

import { AppError } from '../../common/app-error.js';
import type { Env } from '../../config/configuration.js';

/**
 * Admits services/live to the internal directory (ADR-0012) by `X-Internal-Token`. Compared in
 * constant time; the route is also never published by the gateway (infra/docker/Caddyfile).
 */
@Injectable()
export class InternalTokenGuard implements CanActivate {
  private readonly expected: Buffer;

  constructor(config: ConfigService<Env, true>) {
    this.expected = Buffer.from(config.getOrThrow('INTERNAL_API_TOKEN', { infer: true }));
  }

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    const given = Buffer.from(request.header('x-internal-token') ?? '');
    if (given.length !== this.expected.length || !timingSafeEqual(given, this.expected)) {
      throw new AppError('UNAUTHENTICATED', 'internal token required');
    }
    return true;
  }
}
