import { Global, Module } from '@nestjs/common';

import { PrismaService } from './prisma.service.js';

/**
 * Global so every feature module gets the same connection pool without importing it.
 *
 * Providing PrismaService from AppModule alone does not work: Nest resolves a module's providers
 * from that module's own context, so each feature module would need an explicit import.
 */
@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
