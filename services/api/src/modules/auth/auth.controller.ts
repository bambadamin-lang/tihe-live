import { Body, Controller, Get, HttpCode, Post, Req, UsePipes } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import {
  changePasswordBodySchema,
  loginBodySchema,
  refreshBodySchema,
  replaceDeviceBodySchema,
  type ChangePasswordBody,
  type LoginBody,
  type RefreshBody,
  type ReplaceDeviceBody,
} from '@tihe/contracts';
import type { Request } from 'express';

import { PrismaService } from '../../common/prisma.service.js';
import { ZodValidationPipe } from '../../common/zod.pipe.js';
import { DevicesService } from '../devices/devices.service.js';
import { AllowPendingPasswordChange, Public } from './auth.guard.js';
import { AuthService } from './auth.service.js';
import { CurrentUser, type AuthContext } from './current-user.decorator.js';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly devices: DevicesService,
    private readonly prisma: PrismaService,
  ) {}

  @Public()
  @Post('login')
  @HttpCode(200)
  @UsePipes(new ZodValidationPipe(loginBodySchema))
  @ApiOperation({
    summary: 'Sign in with phone and password',
    description:
      'An unknown number and a wrong password answer the same INVALID_CREDENTIALS. When the ' +
      'account already has its limit of devices signed in, answers DEVICE_LIMIT_REACHED with ' +
      'those devices and a five-minute ticket for POST /auth/login/replace.',
  })
  async login(@Body() body: LoginBody, @Req() req: Request) {
    return this.auth.login(body, req.ip);
  }

  @Public()
  @Post('login/replace')
  @HttpCode(200)
  @UsePipes(new ZodValidationPipe(replaceDeviceBodySchema))
  @ApiOperation({
    summary: 'Sign another device out and finish signing in',
    description:
      'Takes the ticket from DEVICE_LIMIT_REACHED, so the password is not typed twice. The ' +
      'ticket only works from the device it was issued to.',
  })
  async replace(@Body() body: ReplaceDeviceBody) {
    return this.auth.replaceDevice(body);
  }

  @Public()
  @Post('refresh')
  @HttpCode(200)
  @UsePipes(new ZodValidationPipe(refreshBodySchema))
  @ApiOperation({
    summary: 'Rotate tokens',
    description:
      'Refresh tokens are single-use. Presenting a consumed token signs the device out, because ' +
      'that indicates the token was captured rather than a benign race.',
  })
  async refresh(@Body() body: RefreshBody) {
    return this.auth.refresh(body.refreshToken);
  }

  @Post('logout')
  @HttpCode(204)
  @AllowPendingPasswordChange()
  @ApiOperation({ summary: 'Sign this device out, which frees its slot' })
  async logout(@CurrentUser() auth: AuthContext) {
    await this.auth.logout(auth.deviceId);
  }

  @Post('password')
  @HttpCode(204)
  @AllowPendingPasswordChange()
  @ApiOperation({
    summary: 'Change the password',
    description: 'Signs the other devices out unless signOutOtherDevices is false.',
  })
  // The pipe goes on the body alone: a method-level pipe would also run on @CurrentUser, which
  // Nest treats as pipeable, and reject the caller's own auth context.
  async changePassword(
    @CurrentUser() auth: AuthContext,
    @Body(new ZodValidationPipe(changePasswordBodySchema)) body: ChangePasswordBody,
  ) {
    await this.auth.changePassword(auth.userId, auth.deviceId, body);
  }

  @Get('me')
  @AllowPendingPasswordChange()
  @ApiOperation({
    summary: 'Current user, device and revocation epoch',
    description:
      'The client compares revocationEpoch against its stored value to notice a revocation it has ' +
      'not yet seen.',
  })
  async me(@CurrentUser() auth: AuthContext) {
    const [user, device] = await Promise.all([
      this.prisma.user.findUniqueOrThrow({ where: { id: auth.userId } }),
      this.prisma.device.findUniqueOrThrow({ where: { id: auth.deviceId } }),
    ]);

    return {
      user: this.auth.userDto(user),
      device: await this.devices.toDto(device, auth.deviceId),
      revocationEpoch: user.revocationEpoch,
    };
  }
}
