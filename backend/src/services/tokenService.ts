/**
 * JWT access tokens + opaque rotating refresh tokens.
 *
 * - Access token: short-lived (default 15 min), carries `sub`, `username`, `role`.
 * - Refresh token: 256-bit random string, stored **hashed**; rotated on every use
 *   and revoked on logout, password change, or account deletion.
 */
import jwt, { type JwtPayload, type SignOptions } from 'jsonwebtoken';
import { env } from '../config/env.js';
import type { User } from '../domain/models.js';
import { getRepositories } from '../repositories/index.js';
import { sha256 } from '../utils/crypto.js';
import { newToken } from '../utils/ids.js';
import { tokenExpired, unauthorized } from '../utils/errors.js';
import { MS_PER_DAY, parseDuration } from '../utils/time.js';

export interface AccessTokenClaims extends JwtPayload {
  sub: string;
  username: string;
  role: User['role'];
  guest: boolean;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  tokenType: 'Bearer';
  expiresIn: number;
  refreshExpiresAt: string;
}

export function signAccessToken(user: User): string {
  const options: SignOptions = {
    expiresIn: env.ACCESS_TOKEN_TTL as SignOptions['expiresIn'],
    issuer: env.JWT_ISSUER,
    subject: user.id,
  };
  return jwt.sign(
    { username: user.username, role: user.role, guest: user.isGuest },
    env.JWT_ACCESS_SECRET,
    options,
  );
}

export function verifyAccessToken(token: string): AccessTokenClaims {
  try {
    return jwt.verify(token, env.JWT_ACCESS_SECRET, {
      issuer: env.JWT_ISSUER,
    }) as AccessTokenClaims;
  } catch (error) {
    if ((error as Error).name === 'TokenExpiredError')
      throw tokenExpired('Access token has expired');
    throw unauthorized('Invalid access token');
  }
}

export async function issueTokenPair(user: User, userAgent: string | null): Promise<TokenPair> {
  const repos = getRepositories();
  const refreshToken = newToken(32);
  const expiresAt = new Date(Date.now() + env.REFRESH_TOKEN_TTL_DAYS * MS_PER_DAY).toISOString();

  await repos.tokens.issue({
    userId: user.id,
    tokenHash: sha256(refreshToken),
    expiresAt,
    userAgent,
  });

  return {
    accessToken: signAccessToken(user),
    refreshToken,
    tokenType: 'Bearer',
    expiresIn: Math.floor(parseDuration(env.ACCESS_TOKEN_TTL) / 1000),
    refreshExpiresAt: expiresAt,
  };
}

/** Validate a refresh token, revoke it, and mint a brand-new pair (rotation). */
export async function rotateRefreshToken(
  refreshToken: string,
  userAgent: string | null,
): Promise<{ user: User; tokens: TokenPair }> {
  const repos = getRepositories();
  const record = await repos.tokens.findByHash(sha256(refreshToken));

  if (!record) throw unauthorized('Refresh token is not recognised');
  if (record.revokedAt) throw unauthorized('Refresh token has been revoked');
  if (Date.parse(record.expiresAt) < Date.now()) throw tokenExpired('Refresh token has expired');

  const user = await repos.users.findById(record.userId);
  if (!user) throw unauthorized('Account no longer exists');
  if (user.isBanned) throw unauthorized('Account is suspended');

  await repos.tokens.revoke(record.id);
  const tokens = await issueTokenPair(user, userAgent);
  await repos.users.touchLastSeen(user.id);
  return { user, tokens };
}

export async function revokeRefreshToken(refreshToken: string): Promise<void> {
  const repos = getRepositories();
  const record = await repos.tokens.findByHash(sha256(refreshToken));
  if (record && !record.revokedAt) await repos.tokens.revoke(record.id);
}
