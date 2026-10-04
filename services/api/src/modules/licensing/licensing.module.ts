import { Global, Module } from '@nestjs/common';

import { LicensingController } from './licensing.controller.js';
import { LicensingService } from './licensing.service.js';

@Global()
@Module({
  controllers: [LicensingController],
  providers: [LicensingService],
  exports: [LicensingService],
})
export class LicensingModule {}
