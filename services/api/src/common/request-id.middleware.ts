import { Injectable, type NestMiddleware } from '@nestjs/common';
import type { NextFunction, Request, Response } from 'express';
import { ulid } from 'ulid';

/**
 * Tags every request with an id, returned in error envelopes and echoed in logs.
 *
 * This is what makes support possible: a student reports a code and an id, and the whole request
 * can be found in the log without guessing from timestamps.
 */
@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  use(req: Request & { requestId?: string }, res: Response, next: NextFunction) {
    const incoming = req.header('x-request-id');
    // An incoming id is echoed so a client can correlate, but it is length-capped: it lands in
    // logs, and an unbounded header would be a log-injection vector.
    req.requestId = incoming && incoming.length <= 64 ? incoming : `req_${ulid()}`;
    res.setHeader('x-request-id', req.requestId);
    next();
  }
}
