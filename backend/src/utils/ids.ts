import { randomBytes, randomUUID } from 'node:crypto';

/** RFC 4122 v4 identifier, used for every primary key. */
export const newId = (): string => randomUUID();

/** URL-safe opaque token (refresh tokens, cursors, device secrets). */
export function newToken(bytes = 32): string {
  return randomBytes(bytes).toString('base64url');
}

/** Short, human-readable code (invite/challenge codes). */
export function newShortCode(length = 8): string {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  const raw = randomBytes(length);
  let out = '';
  for (let i = 0; i < length; i += 1) {
    out += alphabet[raw[i]! % alphabet.length];
  }
  return out;
}
