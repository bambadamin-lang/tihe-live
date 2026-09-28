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
      'Includes what each device holds offline, so the student can decide which one to release ' +
      'when they hit the device limit.',
  })
  async list(@CurrentUser() auth: AuthContext) {
    return { items: await this.devices.listForUser(auth.userId, auth.deviceId) };
  }

  @Delete(':id')
  @HttpCode(204)
  @ApiOperation({
    summary: 'Release a device',
    description:
      'Revokes the device, ends its sessions, and expires its offline downloads — otherwise the ' +
      'released machine would keep playing content it already holds.',
  })
  async release(@CurrentUser() auth: AuthContext, @Param('id') id: string) {
    await this.devices.release(auth.userId, id);
  }
}
