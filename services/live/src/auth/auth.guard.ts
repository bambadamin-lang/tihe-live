import { Inject, Injectable, type CanActivate, type ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';
import { LiveHttpError } from '../http/errors.js';
import { ACCESS_TOKEN_VERIFIER, type AccessTokenVerifier, type Caller } from './access-token.js';

export type AuthedRequest = Request & { caller: Caller };

/** Every route except health and webhooks: a valid services/api access token. */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(@Inject(ACCESS_TOKEN_VERIFIER) private readonly verifier: AccessTokenVerifier) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<AuthedRequest>();
    const header = req.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    const caller = token ? await this.verifier.verify(token) : null;
    if (!caller) throw new LiveHttpError('UNAUTHENTICATED', 'missing or invalid access token');
    req.caller = caller;
    return true;
  }
}
