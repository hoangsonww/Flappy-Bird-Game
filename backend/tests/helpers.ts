import type { Express } from 'express';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { env } from '../src/config/env.js';
import { resetRepositories } from '../src/repositories/index.js';

/** Tables wiped between tests when running against Postgres. */
const TABLES = [
  'challenge_entries',
  'daily_challenges',
  'friendships',
  'user_achievements',
  'refresh_tokens',
  'user_stats',
  'scores',
  'users',
];

/**
 * Return storage to a known-empty state.
 *
 * In-memory: drop the singleton store. Postgres: truncate every mutable table
 * (the `achievements` catalog is reference data seeded by a migration).
 */
export async function resetStorage(): Promise<void> {
  if (env.DB_DRIVER === 'postgres') {
    const { query } = await import('../src/db/pool.js');
    await query(`TRUNCATE ${TABLES.join(', ')} CASCADE`);
    return;
  }
  resetRepositories();
}

/** Empty storage plus a fresh Express app — the standard per-test fixture. */
export async function freshApp(): Promise<Express> {
  await resetStorage();
  return createApp();
}

export interface TestSession {
  username: string;
  accessToken: string;
  refreshToken: string;
  userId: string;
}

export async function registerUser(
  app: Express,
  username: string,
  overrides: Record<string, unknown> = {},
): Promise<TestSession> {
  const response = await request(app)
    .post('/v1/auth/register')
    .send({ username, password: 'flappybird123', ...overrides })
    .expect(201);

  return {
    username,
    accessToken: response.body.tokens.accessToken,
    refreshToken: response.body.tokens.refreshToken,
    userId: response.body.user.id,
  };
}

export const auth = (session: TestSession) => ({ Authorization: `Bearer ${session.accessToken}` });

export interface RunOverrides {
  score?: number;
  mode?: string;
  coins?: number;
  pipesPassed?: number;
  durationMs?: number;
  maxCombo?: number;
  powerUpsUsed?: number;
  seed?: string;
}

/** Build a plausible run payload that passes every anti-cheat heuristic. */
export function runPayload(score: number, overrides: RunOverrides = {}) {
  return {
    score,
    mode: 'classic',
    coins: Math.min(score, 10),
    pipesPassed: score,
    durationMs: Math.max(2_000, score * 1_200 + 2_000),
    maxCombo: Math.min(score, 5),
    powerUpsUsed: 0,
    seed: 'test-seed',
    ...overrides,
  };
}

export async function submitRun(
  app: Express,
  session: TestSession,
  score: number,
  overrides: RunOverrides = {},
) {
  return request(app)
    .post('/v1/scores')
    .set(auth(session))
    .send(runPayload(score, overrides))
    .expect(201);
}
