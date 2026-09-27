import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';

import { PrismaService } from '../../common/prisma.service.js';
import { Public } from '../auth/auth.guard.js';
import { StorageService } from '../storage/storage.service.js';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
  ) {}

  @Public()
  @Get()
  @ApiOperation({ summary: 'Liveness' })
  live() {
    return { status: 'ok', uptimeSeconds: Math.round(process.uptime()) };
  }

  @Public()
  @Get('ready')
  @ApiOperation({
    summary: 'Readiness',
    description:
      'Checks Postgres and object storage. Reports each dependency separately so a partial outage ' +
      'is diagnosable from the response rather than from the logs.',
  })
  async ready() {
    const checks: Record<string, 'ok' | 'fail'> = {};

    try {
      await this.prisma.$queryRaw`SELECT 1`;
      checks.database = 'ok';
    } catch {
      checks.database = 'fail';
    }

    try {
      // Listing a key that does not exist still proves credentials and reachability.
      await this.storage.exists(this.storage.vodBucket, '.readiness-probe');
      checks.storage = 'ok';
    } catch {
      checks.storage = 'fail';
    }

    const ready = Object.values(checks).every((v) => v === 'ok');
    return { status: ready ? 'ok' : 'degraded', checks };
  }
}
