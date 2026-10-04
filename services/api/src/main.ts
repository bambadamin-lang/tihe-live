import 'reflect-metadata';

import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import express from 'express';

import { AppModule } from './app.module.js';
import { ErrorFilter } from './common/error.filter.js';
import type { Env } from './config/configuration.js';

async function bootstrap() {
  const logger = new Logger('bootstrap');
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

  const config = app.get(ConfigService<Env, true>);
  const prefix = config.getOrThrow('API_PREFIX', { infer: true });
  const port = config.getOrThrow('PORT', { infer: true });
  const isProduction = config.getOrThrow('NODE_ENV', { infer: true }) === 'production';

  app.setGlobalPrefix(prefix);
  app.useGlobalFilters(new ErrorFilter());
  // No global ValidationPipe: validation is zod, at each boundary, against the schemas in
  // @tihe/contracts (see common/zod.pipe.ts). class-validator DTOs would be a second, drifting copy
  // of the contract the client is generated from.

  // The LiveKit webhook signature covers the raw bytes, so this route needs the body before JSON
  // parsing rewrites it. Any reserialisation changes key order and breaks the digest check.
  app.use(
    `/${prefix}/webhooks/livekit`,
    express.raw({ type: '*/*', limit: '1mb' }),
    (
      req: express.Request & { rawBody?: Buffer },
      _res: express.Response,
      next: express.NextFunction,
    ) => {
      if (Buffer.isBuffer(req.body)) {
        req.rawBody = req.body;
        try {
          req.body = JSON.parse(req.body.toString('utf8'));
        } catch {
          req.body = {};
        }
      }
      next();
    },
  );

  app.enableCors({
    // The mobile and desktop apps do not send an Origin, so CORS is only relevant to a browser —
    // and protected playback never happens in a browser. Kept narrow deliberately.
    origin: isProduction ? false : true,
    credentials: true,
  });

  app.enableShutdownHooks();

  if (!isProduction) {
    const document = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle('TIHE Live API')
        .setDescription(
          'Protected video library and live-class platform. Content protection design: ' +
            'docs/03-content-protection.md. What it does and does not stop: docs/08-threat-model.md.',
        )
        .setVersion('0.1.0')
        .addBearerAuth()
        .build(),
    );
    SwaggerModule.setup('docs', app, document, {
      jsonDocumentUrl: 'docs-json',
    });
    logger.log(`Swagger UI at http://localhost:${port}/docs`);
  }

  await app.listen(port);
  logger.log(`API listening on http://localhost:${port}/${prefix}`);
}

void bootstrap();
