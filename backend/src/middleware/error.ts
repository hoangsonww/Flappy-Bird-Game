import type { NextFunction, Request, Response } from 'express';
import { logger } from '../config/logger.js';
import { env } from '../config/env.js';
import { AppError, isAppError, notFound } from '../utils/errors.js';

/** Terminal 404 for unmatched routes. */
export function notFoundHandler(req: Request, _res: Response, next: NextFunction): void {
  next(notFound(`No route matches ${req.method} ${req.originalUrl}`));
}

/**
 * Single JSON error shape for the whole API:
 * `{ error: { code, message, details, requestId } }`
 */
export function errorHandler(
  error: unknown,
  req: Request,
  res: Response,
  _next: NextFunction,
): void {
  const appError = normalise(error);

  if (appError.status >= 500) {
    logger.error(
      { err: error, requestId: req.requestId, path: req.originalUrl },
      'Unhandled request failure',
    );
  } else {
    logger.debug(
      { code: appError.code, requestId: req.requestId, path: req.originalUrl },
      appError.message,
    );
  }

  res.status(appError.status).json({
    error: {
      code: appError.code,
      message: appError.expose ? appError.message : 'Unexpected server error',
      details: appError.expose ? appError.details : null,
      requestId: req.requestId,
      ...(env.isProduction || appError.expose ? {} : { stack: (error as Error)?.stack }),
    },
  });
}

function normalise(error: unknown): AppError {
  if (isAppError(error)) return error;

  // Body parser failures surface as SyntaxError with a `body` property.
  if (error instanceof SyntaxError && 'body' in error) {
    return new AppError('bad_request', 'Request body is not valid JSON');
  }
  if ((error as { type?: string })?.type === 'entity.too.large') {
    return new AppError('payload_too_large', 'Request body is too large');
  }
  return new AppError('internal_error', (error as Error)?.message ?? 'Unexpected server error');
}
