import { Module } from '@nestjs/common';

import { InternalTokenGuard } from './internal-token.guard.js';
import { InternalController } from './internal.controller.js';

@Module({
  controllers: [InternalController],
  providers: [InternalTokenGuard],
})
export class InternalModule {}
