import type { NextFunction, Request, Response } from 'express';
import { env } from '../config/env.js';
import { getRepositories } from '../repositories/index.js';
import { forbidden, unauthorized } from '../utils/errors.js';
import { safeEqual } from '../utils/crypto.js';
import { verifyAccessToken } from '../services/tokenService.js';

function bearerToken(req: Request): string | null {
  const header = req.header('authorization');
  if (!header) return null;
  const [scheme, token] = header.split(' ');
  if (!scheme || scheme.toLowerCase() !== 'bearer' || !token) return null;
  return token.trim();
}

/** Reject the request unless a valid, unbanned account is attached. */
export async function requireAuth(req: Request, _res: Response, next: NextFunction): Promise<void> {
  try {
    const token = bearerToken(req);
    if (!token) throw unauthorized('Provide an Authorization: Bearer <accessToken> header');

    const claims = verifyAccessToken(token);
    const user = await getRepositories().users.findById(claims.sub);
    if (!user) throw unauthorized('Account no longer exists');
    if (user.isBanned) throw forbidden(user.banReason ?? 'This account is suspended');

    req.user = user;
    next();
  } catch (error) {
    next(error);
  }
}

/** Attach the account when a token is present, but never fail the request. */
export async function optionalAuth(
  req: Request,
  _res: Response,
  next: NextFunction,
): Promise<void> {
  const token = bearerToken(req);
  if (!token) {
    next();
    return;
  }
  try {
    const claims = verifyAccessToken(token);
    const user = await getRepositories().users.findById(claims.sub);
    if (user && !user.isBanned) req.user = user;
  } catch {
    // An expired or bogus token behaves exactly like an anonymous caller here.
  }
  next();
}

/**
 * Admin gate. Accepts either an `admin` role on the authenticated account or a
 * static `X-Admin-Token` header matching `ADMIN_TOKEN` (handy for local scripts).
 */
export function requireAdmin(req: Request, _res: Response, next: NextFunction): void {
  const headerToken = req.header('x-admin-token');
  if (env.ADMIN_TOKEN && headerToken && safeEqual(env.ADMIN_TOKEN, headerToken)) {
    next();
    return;
  }
  if (req.user?.role === 'admin') {
    next();
    return;
  }
  next(forbidden('Administrator privileges are required'));
}
