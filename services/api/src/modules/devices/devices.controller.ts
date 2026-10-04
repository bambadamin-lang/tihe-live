import { Controller, Delete, Get, HttpCode, Param } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';

import { CurrentUser, type AuthContext } from '../auth/current-user.decorator.js';
import { DevicesService } from './devices.service.js';

@ApiTags('devices')
@Controller('devices')
export class DevicesController {
  constructor(private readonly devices: DevicesService) {}

  @Get()
  @ApiOperation({
    summary: "List the user's devices",
    description:
      'Signed-in devices first: they count towards the limit of devices signed in at once. ' +
      'Includes what each holds offline, so the student can see what signing one out costs.',
  })
  async list(@CurrentUser() auth: AuthContext) {
    return { items: await this.devices.listForUser(auth.userId, auth.deviceId) };
  }

  @Delete(':id')
  @HttpCode(204)
  @ApiOperation({
    summary: 'Sign a device out',
    description:
      'Frees its slot, ends its sessions and playback, and expires its offline downloads — ' +
      'otherwise the signed-out machine would keep playing content it already holds.',
  })
  async signOut(@CurrentUser() auth: AuthContext, @Param('id') id: string) {
    await this.devices.signOut(auth.userId, id);
  }
}
