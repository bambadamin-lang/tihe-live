import 'reflect-metadata';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { INestApplication } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import express from 'express';
import { AppModule, type LiveDeps } from './app.module.js';
import { ClassroomGateway } from './classroom/gateway.js';

export const API_PREFIX = 'v1/live';

/** Build the HTTP app and attach the classroom WebSocket to the same server. */
export async function createLiveApp(
  deps: LiveDeps,
  opts: { logger?: false } = {},
): Promise<INestApplication> {
  const app = await NestFactory.create(AppModule.forRoot(deps), {
    bodyParser: false,
    ...(opts.logger === false && { logger: false }),
  });
  // Webhooks are verified against their exact bytes, so they get the raw text; everything else
  // is JSON with a size cap that fits the largest whiteboard restore.
  app.use(`/${API_PREFIX}/webhooks`, express.text({ type: '*/*', limit: '1mb' }));
  app.use(express.json({ limit: '1mb' }));

  // The Egress recording template, served from here so Egress's Chrome needs only one origin.
  const template = fileURLToPath(new URL('../egress-template/dist', import.meta.url));
  if (existsSync(template)) app.use(`/${API_PREFIX}/egress-template`, express.static(template));

  app.setGlobalPrefix(API_PREFIX);
  app.enableShutdownHooks();
  app.get(ClassroomGateway).attach(app.getHttpServer());
  return app;
}
