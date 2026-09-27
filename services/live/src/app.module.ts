import { Module, type DynamicModule } from '@nestjs/common';
import { APP_FILTER } from '@nestjs/core';
import { ACCESS_TOKEN_VERIFIER, type AccessTokenVerifier } from './auth/access-token.js';
import { AuthGuard } from './auth/auth.guard.js';
import { TicketService } from './auth/tickets.js';
import { ClassAccess } from './classes/access.js';
import { ClassesController } from './classes/classes.controller.js';
import { ClassesService } from './classes/classes.service.js';
import { CLOCK, ClassroomHub, type Clock } from './classroom/classroom-hub.js';
import { ClassroomGateway } from './classroom/gateway.js';
import { ROOM_STORE, type RoomStore } from './classroom/room-store.js';
import { LIVE_CONFIG, type LiveConfig } from './config.js';
import { COURSE_DIRECTORY, type CourseDirectory } from './directory/course-directory.js';
import { HealthController } from './health.controller.js';
import { LiveErrorFilter } from './http/errors.js';
import { LayoutsController } from './layouts/layouts.controller.js';
import { LIVEKIT_PORT, type LiveKitPort } from './livekit/livekit.port.js';
import { LIVE_REPOSITORY, type LiveRepository } from './persistence/live-repository.js';
import { RecordingService } from './recording/recording.service.js';
import { SessionsController } from './sessions/sessions.controller.js';
import { SessionsService } from './sessions/sessions.service.js';
import { OBJECT_STORE, type ObjectStore } from './storage/object-store.js';
import { WebhooksController } from './webhooks/webhooks.controller.js';

/**
 * Everything with a side effect, passed in whole. main.ts builds the real ones from the
 * environment; tests pass in-memory fakes. Nothing inside the app decides which it gets.
 */
export interface LiveDeps {
  config: LiveConfig;
  repo: LiveRepository;
  store: RoomStore;
  livekit: LiveKitPort;
  directory: CourseDirectory;
  objects: ObjectStore;
  verifier: AccessTokenVerifier;
  tickets: TicketService;
  clock: Clock;
}

@Module({})
export class AppModule {
  static forRoot(deps: LiveDeps): DynamicModule {
    return {
      module: AppModule,
      controllers: [
        HealthController,
        ClassesController,
        SessionsController,
        LayoutsController,
        WebhooksController,
      ],
      providers: [
        { provide: LIVE_CONFIG, useValue: deps.config },
        { provide: LIVE_REPOSITORY, useValue: deps.repo },
        { provide: ROOM_STORE, useValue: deps.store },
        { provide: LIVEKIT_PORT, useValue: deps.livekit },
        { provide: COURSE_DIRECTORY, useValue: deps.directory },
        { provide: OBJECT_STORE, useValue: deps.objects },
        { provide: ACCESS_TOKEN_VERIFIER, useValue: deps.verifier },
        { provide: TicketService, useValue: deps.tickets },
        { provide: CLOCK, useValue: deps.clock },
        { provide: APP_FILTER, useClass: LiveErrorFilter },
        AuthGuard,
        ClassAccess,
        ClassesService,
        SessionsService,
        RecordingService,
        ClassroomHub,
        ClassroomGateway,
      ],
    };
  }
}
