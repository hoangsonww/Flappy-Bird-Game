import rateLimit, { type Options } from 'express-rate-limit';
import { env } from '../config/env.js';
import { AppError } from '../utils/errors.js';

function build(max: number, windowMs: number, scope: string): ReturnType<typeof rateLimit> {
  const options: Partial<Options> = {
    windowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    skip: () => env.isTest,
    keyGenerator: (req) => `${scope}:${req.user?.id ?? req.ip ?? 'unknown'}`,
    handler: (_req, _res, next) => {
      next(
        new AppError('rate_limited', 'Too many requests — slow down and try again shortly.', {
          scope,
          windowMs,
          max,
        }),
      );
    },
  };
  return rateLimit(options);
}

/** Default limiter applied to the whole `/v1` surface. */
export const globalLimiter = build(env.RATE_LIMIT_MAX, env.RATE_LIMIT_WINDOW_MS, 'global');

/** Stricter limiter for credential endpoints (brute-force resistance). */
export const authLimiter = build(env.AUTH_RATE_LIMIT_MAX, env.RATE_LIMIT_WINDOW_MS, 'auth');

/** Score submission limiter — generous enough for rapid retries, tight enough to matter. */
export const submitLimiter = build(env.SUBMIT_RATE_LIMIT_MAX, env.RATE_LIMIT_WINDOW_MS, 'submit');
