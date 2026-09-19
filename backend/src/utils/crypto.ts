import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { env } from '../config/env.js';

/** Hash a user password with bcrypt. Cost is configurable via BCRYPT_ROUNDS. */
export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, env.BCRYPT_ROUNDS);
}

/** Constant-time password verification. */
export async function verifyPassword(plain: string, hash: string): Promise<boolean> {
  try {
    return await bcrypt.compare(plain, hash);
  } catch {
    return false;
  }
}

/** SHA-256 hex digest. Refresh tokens are stored hashed, never in plaintext. */
export function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

/**
 * HMAC-SHA256 signature of a canonical run summary.
 *
 * The iOS client can sign every submitted run with a shared secret so the
 * server can reject payloads that were not produced by the real game build.
 * Canonical form: `mode|score|coins|pipes|durationMs|seed`.
 */
export function signRun(input: {
  mode: string;
  score: number;
  coins: number;
  pipesPassed: number;
  durationMs: number;
  seed: string;
}): string {
  const canonical = [
    input.mode,
    input.score,
    input.coins,
    input.pipesPassed,
    input.durationMs,
    input.seed,
  ].join('|');
  return createHmac('sha256', env.RUN_SIGNING_SECRET).update(canonical).digest('hex');
}

/** Constant-time string comparison that tolerates different lengths. */
export function safeEqual(a: string, b: string): boolean {
  const bufferA = Buffer.from(a);
  const bufferB = Buffer.from(b);
  if (bufferA.length !== bufferB.length) return false;
  return timingSafeEqual(bufferA, bufferB);
}
