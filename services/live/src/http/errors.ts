import { ArgumentsHost, Catch, HttpException, Logger, type ExceptionFilter } from '@nestjs/common';
import { ERROR_CATALOG, type ErrorCode, type ErrorResponse } from '@tihe/contracts';
import type { Request, Response } from 'express';
import { ZodError, type ZodTypeAny, type z } from 'zod';
import { ulid } from 'ulid';

/** A failure with a stable code; the filter turns it into the shared error envelope. */
export class LiveHttpError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
  }
}

export function parseOrThrow<S extends ZodTypeAny>(schema: S, value: unknown): z.infer<S> {
  const result = schema.safeParse(value);
  if (!result.success) {
    throw new LiveHttpError('VALIDATION_FAILED', 'request failed validation', {
      issues: result.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
    });
  }
  return result.data;
}

/**
 * Every error leaves in the envelope from docs/05-api-contracts.md, with its Persian message.
 * Unknown errors are logged with the request id and never echoed to the client.
 */
@Catch()
export class LiveErrorFilter implements ExceptionFilter {
  private readonly logger = new Logger('LiveErrorFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const res = host.switchToHttp().getResponse<Response>();
    const req = host.switchToHttp().getRequest<Request>();
    const requestId = (req.headers['x-request-id'] as string | undefined) ?? `req_${ulid()}`;

    let code: ErrorCode = 'INTERNAL';
    let message = 'internal error';
    let details: Record<string, unknown> | undefined;
    if (exception instanceof LiveHttpError) {
      ({ code, message, details } = exception);
    } else if (exception instanceof ZodError) {
      code = 'VALIDATION_FAILED';
      message = 'request failed validation';
    } else if (exception instanceof HttpException) {
      const status = exception.getStatus();
      code =
        status === 404
          ? 'NOT_FOUND'
          : status === 401
            ? 'UNAUTHENTICATED'
            : status < 500
              ? 'VALIDATION_FAILED'
              : 'INTERNAL';
      message = exception.message;
    }
    if (code === 'INTERNAL') {
      this.logger.error(
        `${requestId} ${req.method} ${req.path}`,
        exception instanceof Error ? exception.stack : exception,
      );
      message = 'internal error';
    }

    const body: ErrorResponse = {
      error: {
        code,
        message,
        messageFa: ERROR_CATALOG[code].messageFa,
        requestId,
        ...(details ? { details } : {}),
      },
    };
    res.status(ERROR_CATALOG[code].http).json(body);
  }
}
