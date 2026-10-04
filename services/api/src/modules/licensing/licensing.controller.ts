import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { z } from 'zod';

import { id } from '@tihe/contracts';
import { Roles } from '../auth/auth.guard.js';
import { CurrentUser, type AuthContext } from '../auth/current-user.decorator.js';
import { PrismaService } from '../../common/prisma.service.js';
import { AppError } from '../../common/app-error.js';
import { LicensingService } from './licensing.service.js';

const issueBodySchema = z.object({
  userId: id('user'),
  courseIds: z.array(id('course')).default([]),
  videoIds: z.array(id('video')).default([]),
  notBefore: z.string().datetime().optional(),
  notAfter: z.string().datetime().optional(),
  maxDevices: z.number().int().positive().max(10).optional(),
  offlineWindowDays: z.number().int().positive().max(365).optional(),
});

const revokeBodySchema = z.object({
  reason: z.string().min(3).max(500),
});

@ApiTags('licensing')
@Controller('licenses')
export class LicensingController {
  constructor(
    private readonly licensing: LicensingService,
    private readonly prisma: PrismaService,
  ) {}

  @Post('issue')
  @Roles('admin')
  @ApiOperation({
    summary: 'Issue a licence (admin)',
    description:
      'Policy (device count, offline window) is taken from the courses in scope rather than the ' +
      'request, so an admin mistake cannot hand out a longer offline window than a course allows.',
  })
  async issue(@CurrentUser() auth: AuthContext, @Body() body: unknown) {
    const parsed = issueBodySchema.parse(body);
    const license = await this.licensing.issue({
      userId: parsed.userId,
      courseIds: parsed.courseIds,
      videoIds: parsed.videoIds,
      notBefore: parsed.notBefore ? new Date(parsed.notBefore) : undefined,
      notAfter: parsed.notAfter ? new Date(parsed.notAfter) : undefined,
      maxDevices: parsed.maxDevices,
      offlineWindowDays: parsed.offlineWindowDays,
      issuedBy: auth.userId,
    });

    return {
      id: license.id,
      notBefore: license.notBefore.toISOString(),
      notAfter: license.notAfter.toISOString(),
      maxDevices: license.maxDevices,
      offlineWindowDays: license.offlineWindowDays,
      revocationEpoch: license.revocationEpoch,
      deviceIds: license.devices.map((d) => d.deviceId),
      signedBlob: license.signedBlob,
      signature: license.signature,
    };
  }

  @Get(':id')
  @ApiOperation({
    summary: 'Licence state',
    description:
      'A student may read their own licences; an admin may read any. The stored signed blob is ' +
      'returned as issued, which is what makes a licence dispute answerable.',
  })
  async get(@CurrentUser() auth: AuthContext, @Param('id') licenseId: string) {
    const license = await this.prisma.license.findUnique({
      where: { id: licenseId },
      include: { devices: true },
    });

    if (!license) throw AppError.notFound('licence');
    if (license.userId !== auth.userId && auth.role !== 'admin') {
      throw AppError.forbidden('not your licence');
    }

    return {
      id: license.id,
      userId: license.userId,
      scope: license.scope,
      notBefore: license.notBefore.toISOString(),
      notAfter: license.notAfter.toISOString(),
      maxDevices: license.maxDevices,
      offlineWindowDays: license.offlineWindowDays,
      revocationEpoch: license.revocationEpoch,
      revokedAt: license.revokedAt?.toISOString() ?? null,
      revokedReason: license.revokedReason,
      devices: license.devices.map((d) => ({
        deviceId: d.deviceId,
        boundAt: d.boundAt.toISOString(),
        releasedAt: d.releasedAt?.toISOString() ?? null,
      })),
      signedBlob: license.signedBlob,
      signature: license.signature,
    };
  }

  @Post(':id/revoke')
  @Roles('admin')
  @ApiOperation({
    summary: 'Revoke a licence (admin)',
    description:
      "Increments the user's revocation epoch, which is what reaches offline devices: a device " +
      'holding a lower epoch discards its keys at its next contact. Live sessions end immediately.',
  })
  async revoke(
    @CurrentUser() auth: AuthContext,
    @Param('id') licenseId: string,
    @Body() body: unknown,
  ) {
    const parsed = revokeBodySchema.parse(body);
    const license = await this.licensing.revoke(licenseId, parsed.reason, auth.userId);
    return { id: license.id, revokedAt: license.revokedAt?.toISOString() ?? null };
  }
}
