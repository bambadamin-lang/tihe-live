import { type CanActivate, type ExecutionContext, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';

import { AppError } from '../../common/app-error.js';
import { PrismaService } from '../../common/prisma.service.js';
import type { AuthContext } from './current-user.decorator.js';
import { TokenService } from './tokens.js';

export const IS_PUBLIC = 'isPublic';
/** Marks an endpoint as reachable without a token. */
export const Public = () => SetMetadata(IS_PUBLIC, true);

export const REQUIRED_ROLES = 'requiredRoles';
export const Roles = (...roles: Array<'student' | 'teacher' | 'admin'>) =>
  SetMetadata(REQUIRED_ROLES, roles);

export const ALLOW_PENDING_PASSWORD = 'allowPendingPassword';
/**
 * Reachable while the account still has an admin-set password, so the student can choose their
 * own (and sign out). Everything else answers PASSWORD_CHANGE_REQUIRED until they do.
 */
export const AllowPendingPasswordChange = () => SetMetadata(ALLOW_PENDING_PASSWORD, true);

/**
 * Verifies the access token and loads the user and device.
 *
 * Deliberately hits the database on every request rather than trusting the token's claims alone.
 * A 15-minute access token would otherwise keep working for 15 minutes after a device is signed
 * out or an account suspended — and "revocation takes effect immediately" is a property this
 * product sells. The token's `sid` must still be the device's session: signing a device out, from
 * anywhere, ends every token it holds at once (ADR-0014).
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly tokens: TokenService,
    private readonly prisma: PrismaService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, targets)) return true;

    const request = context.switchToHttp().getRequest<Request & { auth?: AuthContext }>();
    const header = request.header('authorization');

    if (!header?.startsWith('Bearer ')) {
      throw new AppError('UNAUTHENTICATED', 'missing bearer token');
    }

    const claims = await this.tokens.verifyAccess(header.slice(7));
    if (!claims) throw new AppError('TOKEN_EXPIRED', 'invalid or expired access token');

    const device = await this.prisma.device.findUnique({
      where: { id: claims.did },
      include: { user: true },
    });

    if (!device || device.userId !== claims.sub) throw new AppError('DEVICE_UNKNOWN');
    if (device.revokedAt) throw new AppError('DEVICE_REVOKED');
    if (device.sessionId !== claims.sid) throw new AppError('DEVICE_SIGNED_OUT');
    if (device.user.status === 'suspended') throw new AppError('ACCOUNT_SUSPENDED');

    if (
      device.user.mustChangePassword &&
      !this.reflector.getAllAndOverride<boolean>(ALLOW_PENDING_PASSWORD, targets)
    ) {
      throw new AppError('PASSWORD_CHANGE_REQUIRED');
    }

    request.auth = {
      userId: device.userId,
      deviceId: device.id,
      role: device.user.role,
      revocationEpoch: device.user.revocationEpoch,
    };

    const requiredRoles = this.reflector.getAllAndOverride<string[]>(REQUIRED_ROLES, targets);
    if (requiredRoles?.length && !requiredRoles.includes(device.user.role)) {
      throw new AppError('FORBIDDEN', `requires role: ${requiredRoles.join(' or ')}`);
    }

    // Fire-and-forget: a failed last-seen update must not fail the request.
    void this.prisma.device
      .update({ where: { id: device.id }, data: { lastSeenAt: new Date() } })
      .catch(() => undefined);

    return true;
  }
}
