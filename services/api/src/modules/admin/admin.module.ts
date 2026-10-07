import { Module } from '@nestjs/common';

import { DevicesModule } from '../devices/devices.module.js';
import { AdminController } from './admin.controller.js';
import { AdminService } from './admin.service.js';

@Module({
  imports: [DevicesModule],
  controllers: [AdminController],
  providers: [AdminService],
})
export class AdminModule {}
