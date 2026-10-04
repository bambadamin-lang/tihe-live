import {
  type ArgumentsHost,
  Catch,
  type ExceptionFilter,
  HttpException,
  Logger,
} from '@nestjs/common';
import { ERROR_CATALOG, type ErrorCode, type ErrorResponse } from '@tihe/contracts';
import type { Request, Response } from 'express';
import { ZodError } from 'zod';

import { AppError } from './app-error.js';

/**
 * Turns every thrown error into the single response envelope the client expects.
 *
 * One rule drives the shape: a client must never have to parse a message to decide what to do.
 * It switches on `code`, shows `messageFa`, and reports `requestId` to support.
 */
@Catch()
export class ErrorFilter implements ExceptionFilter {
  private readonly logger = new Logger('ErrorFilter');

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request & { requestId?: string }>();
    const requestId = request.requestId ?? 'unknown';

    const { code, message, details } = this.classify(exception);
    const entry = ERROR_CATALOG[code];

    // 5xx means we broke something, so log the stack. 4xx is the client being told no, which is
    // ordinary traffic and not worth a stack trace.
    if (entry.http >= 500) {
      this.logger.error(
        `${request.method} ${request.url} [${requestId}] ${code}: ${message}`,
        exception instanceof Error ? exception.stack : undefined,
      );
    } else {
      this.logger.debug(`${request.method} ${request.url} [${requestId}] ${code}: ${message}`);
    }

    const body: ErrorResponse = {
      error: {
        code,
        message,
        messageFa: entry.messageFa,
        ...(details ? { details } : {}),
        requestId,
      },
    };

    response.status(entry.http).json(body);
  }

  private classify(exception: unknown): {
    code: ErrorCode;
    message: string;
    details?: Record<string, unknown>;
  } {
    if (exception instanceof AppError) {
      return { code: exception.code, message: exception.message, details: exception.details };
    }

    // Structural check rather than `instanceof` alone. A ZodError crossing a module boundary can
    // come from a different copy of zod than the one imported here (a CJS/ESM split, or two
    // resolved versions), and `instanceof` silently fails — turning every validation error into a
    // 500 with the wrong Persian message. The contracts package emits CommonJS to avoid that split,
    // and this check means a future one cannot reintroduce the bug.
    if (isZodError(exception)) {
      return {
        code: 'VALIDATION_FAILED',
        message: 'request failed schema validation',
        details: {
          issues: exception.issues.map((i) => ({
            path: i.path.join('.'),
            message: i.message,
          })),
        },
      };
    }

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const code: ErrorCode =
        status === 401
          ? 'UNAUTHENTICATED'
          : status === 403
            ? 'FORBIDDEN'
            : status === 404
              ? 'NOT_FOUND'
              : status === 429
                ? 'RATE_LIMITED'
                : status < 500
                  ? 'VALIDATION_FAILED'
                  : 'INTERNAL';
      return { code, message: exception.message };
    }

    // Anything unrecognised is a bug. Return the generic envelope — an internal message could
    // disclose a query, a path or a key name.
    return {
      code: 'INTERNAL',
      message: exception instanceof Error ? exception.message : 'unexpected error',
    };
  }
}

/** A zod issue as it appears on a ZodError, from whichever copy of zod produced it. */
interface ZodIssueLike {
  path: Array<string | number>;
  message: string;
}

function isZodError(value: unknown): value is { issues: ZodIssueLike[] } {
  if (value instanceof ZodError) return true;
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as { name?: unknown }).name === 'ZodError' &&
    Array.isArray((value as { issues?: unknown }).issues)
  );
}
