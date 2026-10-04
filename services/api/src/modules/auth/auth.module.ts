import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';

import type { Env } from '../../config/configuration.js';
import { DevicesModule } from '../devices/devices.module.js';
import { AuthController } from './auth.controller.js';
import { AuthGuard } from './auth.guard.js';
import { AuthService } from './auth.service.js';
import { PasswordHasher } from '@tihe/crypto';
import { TokenService } from './tokens.js';

@Global()
@Module({
  imports: [
    DevicesModule,
    JwtModule.registerAsync({
      inject: [ConfigService],
      // Issuer and audience are set per token (TokenService), because access tokens and
      // device-limit tickets must never be accepted as each other.
      useFactory: (config: ConfigService<Env, true>) => ({
        secret: config.getOrThrow('JWT_SECRET', { infer: true }),
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    AuthGuard,
    TokenService,
    {
      provide: PasswordHasher,
      inject: [ConfigService],
      useFactory: (config: ConfigService<Env, true>) =>
        new PasswordHasher(config.getOrThrow('PASSWORD_PEPPER', { infer: true })),
    },
  ],
  // TokenService and JwtModule are exported because AuthGuard is registered as an APP_GUARD in
  // AppModule, so Nest resolves its dependencies from AppModule's context rather than this one.
  exports: [AuthService, AuthGuard, TokenService, PasswordHasher, JwtModule],
})
export class AuthModule {}
