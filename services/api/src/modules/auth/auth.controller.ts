import { Body, Controller, Get, HttpCode, Post, Req, UsePipes } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import {
  maskPhone,
  otpRequestBodySchema,
  otpVerifyBodySchema,
  refreshBodySchema,
  type OtpRequestBody,
  type OtpVerifyBody,
  type RefreshBody,
} from '@tihe/contracts';
import type { Request } from 'express';

import { PrismaService } from '../../common/prisma.service.js';
import { ZodValidationPipe } from '../../common/zod.pipe.js';
import { DevicesService } from '../devices/devices.service.js';
import { AuthService } from './auth.service.js';
import { Public } from './auth.guard.js';
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
  @Post('otp/request')
  @UsePipes(new ZodValidationPipe(otpRequestBodySchema))
  @ApiOperation({
    summary: 'Request an SMS code',
    description:
      'The response is identical whether or not the number belongs to a registered student, so ' +
      'this endpoint cannot be used to enumerate who studies here. In development the code is ' +
      'returned as devCode and also printed to the API log.',
  })
  async requestOtp(@Body() body: OtpRequestBody, @Req() req: Request) {
    return this.auth.requestOtp(body.phone, req.ip, req.header('user-agent'));
  }

  @Public()
  @Post('otp/verify')
  @UsePipes(new ZodValidationPipe(otpVerifyBodySchema))
  @ApiOperation({
    summary: 'Verify a code and sign in',
    description:
      'Registers the device on first sight, so a student is never authenticated but unable to ' +
      'play anything for lack of a registered device. Fails with DEVICE_LIMIT_REACHED when the ' +
      'allowance is used up; the client should then offer to release a device.',
  })
  async verifyOtp(@Body() body: OtpVerifyBody, @Req() req: Request) {
    return this.auth.verifyOtp(body.phone, body.code, body.device, req.ip);
  }

  @Public()
  @Post('refresh')
  @UsePipes(new ZodValidationPipe(refreshBodySchema))
  @ApiOperation({
    summary: 'Rotate tokens',
    description:
      'Refresh tokens are single-use. Presenting a consumed token revokes the whole device ' +
      'session, because that indicates the token was captured rather than a benign race.',
  })
  async refresh(@Body() body: RefreshBody) {
    return this.auth.refresh(body.refreshToken);
  }

  @Post('logout')
  @HttpCode(204)
  @ApiOperation({ summary: 'Revoke this device session' })
  async logout(@CurrentUser() auth: AuthContext) {
    await this.auth.logout(auth.deviceId);
  }

  @Get('me')
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
      user: {
        id: user.id,
        phoneMasked: maskPhone(user.phone),
        displayName: user.displayName,
        role: user.role,
        status: user.status,
        createdAt: user.createdAt.toISOString(),
      },
      device: await this.devices.toDto(device, auth.deviceId),
      revocationEpoch: user.revocationEpoch,
    };
  }
}
