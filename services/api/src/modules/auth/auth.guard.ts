import { type CanActivate, type ExecutionContext, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import type { Request } from 'express';

import { AppError } from '../../common/app-error.js';
import { PrismaService } from '../../common/prisma.service.js';
import type { AuthContext } from './current-user.decorator.js';

export const IS_PUBLIC = 'isPublic';
/** Marks an endpoint as reachable without a token. */
export const Public = () => SetMetadata(IS_PUBLIC, true);

export const REQUIRED_ROLES = 'requiredRoles';
export const Roles = (...roles: Array<'student' | 'teacher' | 'admin'>) =>
  SetMetadata(REQUIRED_ROLES, roles);

/**
 * Verifies the access token and loads the user and device.
 *
 * Deliberately hits the database on every request rather than trusting the token's claims alone.
 * A 15-minute access token would otherwise keep working for 15 minutes after an admin revokes a
 * device or suspends an account — and "revocation takes effect immediately" is a property this
 * product sells. The row is small, indexed, and the query is cheap next to that guarantee.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<Request & { auth?: AuthContext }>();
    const header = request.header('authorization');

    if (!header?.startsWith('Bearer ')) {
      throw new AppError('UNAUTHENTICATED', 'missing bearer token');
    }

    let payload: { sub: string; did: string };
    try {
      payload = await this.jwt.verifyAsync(header.slice(7));
    } catch {
      throw new AppError('TOKEN_EXPIRED', 'invalid or expired access token');
    }

    const device = await this.prisma.device.findUnique({
      where: { id: payload.did },
      include: { user: true },
    });

    if (!device || device.userId !== payload.sub) {
      throw new AppError('DEVICE_UNKNOWN');
    }
    if (device.revokedAt) {
      throw new AppError('DEVICE_REVOKED');
    }
    if (device.user.status === 'suspended') {
      throw new AppError('FORBIDDEN', 'account suspended');
    }

    request.auth = {
      userId: device.userId,
      deviceId: device.id,
      role: device.user.role,
      revocationEpoch: device.user.revocationEpoch,
    };

    const requiredRoles = this.reflector.getAllAndOverride<string[]>(REQUIRED_ROLES, [
      context.getHandler(),
      context.getClass(),
    ]);
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
