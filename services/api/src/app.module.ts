import { type MiddlewareConsumer, Module, type NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';

import { PrismaModule } from './common/prisma.module.js';
import { RequestIdMiddleware } from './common/request-id.middleware.js';
import { validateEnv } from './config/configuration.js';
import { AuthGuard } from './modules/auth/auth.guard.js';
import { AuthModule } from './modules/auth/auth.module.js';
import { CatalogModule } from './modules/catalog/catalog.module.js';
import { DevicesModule } from './modules/devices/devices.module.js';
import { HealthModule } from './modules/health/health.module.js';
import { LicensingModule } from './modules/licensing/licensing.module.js';
import { PlaybackModule } from './modules/playback/playback.module.js';
import { ProgressModule } from './modules/progress/progress.module.js';
import { StorageModule } from './modules/storage/storage.module.js';
import { WebhooksModule } from './modules/webhooks/webhooks.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      // Validated at boot: a missing KEK should stop the process, not surface as a decryption
      // failure on the first playback request.
      validate: validateEnv,
    }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }]),
    PrismaModule,
    StorageModule,
    AuthModule,
    DevicesModule,
    LicensingModule,
    CatalogModule,
    ProgressModule,
    PlaybackModule,
    WebhooksModule,
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
