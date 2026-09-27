import { Logger } from '@nestjs/common';
import { Redis } from 'ioredis';
import { Hs256AccessTokenVerifier } from './auth/access-token.js';
import { TicketService } from './auth/tickets.js';
import { createLiveApp } from './bootstrap.js';
import { MemoryRoomStore, RedisRoomStore } from './classroom/room-store.js';
import { livekitApiUrl, loadConfig } from './config.js';
import { HttpCourseDirectory } from './directory/http-directory.js';
import { StubCourseDirectory } from './directory/stub-directory.js';
import { LiveKitAdapter } from './livekit/livekit.adapter.js';
import { MemoryLiveRepository } from './persistence/memory-repository.js';
import { PrismaLiveRepository } from './persistence/prisma-repository.js';
import { MemoryObjectStore, S3ObjectStore } from './storage/object-store.js';

const logger = new Logger('services/live');
const config = loadConfig();

if (!config.LIVE_DATABASE_URL) logger.warn('LIVE_DATABASE_URL unset: classes are kept in memory');
if (!config.REDIS_URL) logger.warn('REDIS_URL unset: live rooms will not survive a restart');
if (!config.S3_ENDPOINT) logger.warn('S3_ENDPOINT unset: metadata.json is kept in memory');

const app = await createLiveApp({
  config,
  repo: config.LIVE_DATABASE_URL
    ? new PrismaLiveRepository(config.LIVE_DATABASE_URL)
    : new MemoryLiveRepository(),
  store: config.REDIS_URL ? new RedisRoomStore(new Redis(config.REDIS_URL)) : new MemoryRoomStore(),
  livekit: new LiveKitAdapter(
    livekitApiUrl(config),
    config.LIVEKIT_API_KEY,
    config.LIVEKIT_API_SECRET,
    config.LIVEKIT_WEBHOOK_ALLOW_UNSIGNED,
  ),
  directory:
    config.DIRECTORY_MODE === 'http'
      ? new HttpCourseDirectory(config.API_INTERNAL_URL ?? '', config.API_INTERNAL_TOKEN ?? '')
      : StubCourseDirectory.fromFile(config.DIRECTORY_STUB_FILE),
  objects:
    config.S3_ENDPOINT && config.S3_ACCESS_KEY && config.S3_SECRET_KEY
      ? new S3ObjectStore(
          {
            endpoint: config.S3_ENDPOINT,
            region: config.S3_REGION,
            accessKey: config.S3_ACCESS_KEY,
            secretKey: config.S3_SECRET_KEY,
            forcePathStyle: config.S3_FORCE_PATH_STYLE,
          },
          config.S3_BUCKET_RAW,
        )
      : new MemoryObjectStore(),
  verifier: new Hs256AccessTokenVerifier(config.JWT_SECRET),
  tickets: new TicketService(
    config.LIVE_TICKET_SECRET,
    config.LIVEKIT_API_KEY,
    config.LIVEKIT_API_SECRET,
  ),
  clock: () => new Date(),
});

await app.listen(config.PORT);
logger.log(`listening on :${config.PORT} — REST /v1/live, WebSocket /v1/live/ws`);
