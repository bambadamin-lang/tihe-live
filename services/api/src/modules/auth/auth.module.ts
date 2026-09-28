import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';

import type { Env } from '../../config/configuration.js';
import { DevicesModule } from '../devices/devices.module.js';
import { AuthController } from './auth.controller.js';
import { AuthGuard } from './auth.guard.js';
import { AuthService } from './auth.service.js';
import {
  ConsoleSmsProvider,
  KavenegarSmsProvider,
  SMS_PROVIDER,
  type SmsProvider,
} from './sms.provider.js';

@Global()
@Module({
  imports: [
    DevicesModule,
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService<Env, true>) => ({
        secret: config.getOrThrow('JWT_SECRET', { infer: true }),
        signOptions: { issuer: 'tihe-live' },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    AuthGuard,
    {
      // Chosen at boot from configuration, so the production path cannot silently fall through to
      // the console driver when an API key is missing — it fails to start instead.
      provide: SMS_PROVIDER,
      inject: [ConfigService],
      useFactory: (config: ConfigService<Env, true>): SmsProvider =>
        config.getOrThrow('SMS_PROVIDER', { infer: true }) === 'kavenegar'
          ? new KavenegarSmsProvider(config)
          : new ConsoleSmsProvider(),
    },
  ],
  // JwtModule is re-exported because AuthGuard is registered as an APP_GUARD in AppModule, so
  // Nest resolves its dependencies from AppModule's context rather than this module's.
  exports: [AuthService, AuthGuard, JwtModule],
})
export class AuthModule {}
