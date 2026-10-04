import { type MiddlewareConsumer, Module, type NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';

import { PrismaModule } from './common/prisma.module.js';
import { RequestIdMiddleware } from './common/request-id.middleware.js';
import { validateEnv } from './config/configuration.js';
import { AuthGuard } from './modules/auth/auth.guard.js';
import { AdminModule } from './modules/admin/admin.module.js';
import { AuthModule } from './modules/auth/auth.module.js';
import { CatalogModule } from './modules/catalog/catalog.module.js';
import { DevicesModule } from './modules/devices/devices.module.js';
import { HealthModule } from './modules/health/health.module.js';
import { InternalModule } from './modules/internal/internal.module.js';
import { LicensingModule } from './modules/licensing/licensing.module.js';
import { PlaybackModule } from './modules/playback/playback.module.js';
import { ProgressModule } from './modules/progress/progress.module.js';
import { SettingsModule } from './modules/settings/settings.module.js';
import { StorageModule } from './modules/storage/storage.module.js';
import { WebhooksModule } from './modules/webhooks/webhooks.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      // One env file for the whole workspace, at the repo root. A service-local .env still wins if
      // one exists, which is useful for running two API instances against different databases.
      envFilePath: ['.env', '../../.env'],
      // Validated at boot: a missing KEK should stop the process, not surface as a decryption
      // failure on the first playback request.
      validate: validateEnv,
    }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }]),
    PrismaModule,
    SettingsModule,
    StorageModule,
    AuthModule,
    DevicesModule,
    LicensingModule,
    CatalogModule,
    ProgressModule,
    PlaybackModule,
    WebhooksModule,
    AdminModule,
    InternalModule,
    HealthModule,
  ],
  providers: [
    // Order matters: throttling runs before authentication, so an unauthenticated flood is cheap
    // to reject.
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestIdMiddleware).forRoutes('*');
  }
}
