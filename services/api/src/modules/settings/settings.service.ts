import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  deviceLimitSchema,
  type InstituteSettings,
  type UpdateSettingsBody,
} from '@tihe/contracts';
import type { Prisma } from '@tihe/db';

import { PrismaService } from '../../common/prisma.service.js';
import type { Env } from '../../config/configuration.js';

const DEFAULT_MAX_DEVICES = 'default_max_devices';

type Db = PrismaService | Prisma.TransactionClient;

/**
 * Institute-wide settings an admin changes in the app (ADR-0014). Read on every sign-in, from the
 * database rather than a cache, so a change applies to the very next sign-in on every API
 * instance.
 */
@Injectable()
export class SettingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService<Env, true>,
  ) {}

  async defaultMaxDevices(db: Db = this.prisma): Promise<number> {
    const row = await db.setting.findUnique({ where: { key: DEFAULT_MAX_DEVICES } });
    const parsed = deviceLimitSchema.safeParse(row?.value);
    // An unreadable row falls back to the environment rather than locking everyone out.
    return parsed.success
      ? parsed.data
      : this.config.getOrThrow('DEFAULT_MAX_DEVICES', { infer: true });
  }

  async get(): Promise<InstituteSettings> {
    return { defaultMaxDevices: await this.defaultMaxDevices() };
  }

  async update(body: UpdateSettingsBody, adminId: string): Promise<InstituteSettings> {
    if (body.defaultMaxDevices !== undefined) {
      await this.prisma.setting.upsert({
        where: { key: DEFAULT_MAX_DEVICES },
        create: { key: DEFAULT_MAX_DEVICES, value: body.defaultMaxDevices, updatedBy: adminId },
        update: { value: body.defaultMaxDevices, updatedBy: adminId },
      });
    }
    return this.get();
  }
}
