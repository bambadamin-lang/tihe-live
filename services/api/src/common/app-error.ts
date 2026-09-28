import { HttpException } from '@nestjs/common';
import { ERROR_CATALOG, type ErrorCode } from '@tihe/contracts';

/**
 * The only error type the application throws deliberately.
 *
 * Carrying the code rather than the message means the HTTP status and the Persian text come from
 * one table (`ERROR_CATALOG` in @tihe/contracts), so an endpoint cannot accidentally return a
 * 500 for an expired licence, and no user-facing string is written twice.
 */
export class AppError extends HttpException {
  constructor(
    readonly code: ErrorCode,
    message?: string,
    readonly details?: Record<string, unknown>,
  ) {
    const entry = ERROR_CATALOG[code];
    super(message ?? entry.messageFa, entry.http);
  }

  static notFound(what = 'resource') {
    return new AppError('NOT_FOUND', `${what} not found`);
  }

  static forbidden(why = 'not permitted') {
    return new AppError('FORBIDDEN', why);
  }
}
