/**
 * Typed application errors.
 *
 * Every error surfaces as a stable, machine-readable JSON envelope:
 *
 * ```json
 * { "error": { "code": "not_found", "message": "User not found", "details": null, "requestId": "..." } }
 * ```
 */

export type ErrorCode =
  | 'bad_request'
  | 'validation_failed'
  | 'unauthorized'
  | 'invalid_credentials'
  | 'token_expired'
  | 'forbidden'
  | 'not_found'
  | 'conflict'
  | 'rate_limited'
  | 'payload_too_large'
  | 'unprocessable'
  | 'service_unavailable'
  | 'internal_error';

const STATUS_BY_CODE: Record<ErrorCode, number> = {
  bad_request: 400,
  validation_failed: 422,
  unauthorized: 401,
  invalid_credentials: 401,
  token_expired: 401,
  forbidden: 403,
  not_found: 404,
  conflict: 409,
  rate_limited: 429,
  payload_too_large: 413,
  unprocessable: 422,
  service_unavailable: 503,
  internal_error: 500,
};

export class AppError extends Error {
  readonly code: ErrorCode;
  readonly status: number;
  readonly details: unknown;
  readonly expose: boolean;

  constructor(code: ErrorCode, message: string, details: unknown = null) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.status = STATUS_BY_CODE[code];
    this.details = details;
    this.expose = this.status < 500;
    Error.captureStackTrace?.(this, AppError);
  }

  toJSON() {
    return { code: this.code, message: this.message, details: this.details };
  }
}

export const badRequest = (message: string, details?: unknown) =>
  new AppError('bad_request', message, details ?? null);
export const validationFailed = (message: string, details?: unknown) =>
  new AppError('validation_failed', message, details ?? null);
export const unauthorized = (message = 'Authentication required') =>
  new AppError('unauthorized', message);
export const invalidCredentials = (message = 'Invalid username or password') =>
  new AppError('invalid_credentials', message);
export const tokenExpired = (message = 'Token has expired') =>
  new AppError('token_expired', message);
export const forbidden = (message = 'You do not have access to this resource') =>
  new AppError('forbidden', message);
export const notFound = (message = 'Resource not found') => new AppError('not_found', message);
export const conflict = (message: string, details?: unknown) =>
  new AppError('conflict', message, details ?? null);
export const unprocessable = (message: string, details?: unknown) =>
  new AppError('unprocessable', message, details ?? null);
export const serviceUnavailable = (message = 'Dependency unavailable') =>
  new AppError('service_unavailable', message);
export const internalError = (message = 'Unexpected server error') =>
  new AppError('internal_error', message);

export function isAppError(value: unknown): value is AppError {
  return value instanceof AppError;
}
