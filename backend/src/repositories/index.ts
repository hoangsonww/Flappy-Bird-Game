/**
 * Storage factory.
 *
 * `DB_DRIVER=memory` (default) keeps everything in process — the API is fully
 * functional with zero infrastructure. `DB_DRIVER=postgres` uses the real
 * schema in `backend/migrations`.
 */
import { env } from '../config/env.js';
import { logger } from '../config/logger.js';
import { createMemoryRepositories, resetMemoryStore } from './memory/index.js';
import { createPostgresRepositories } from './postgres/index.js';
import type { Repositories } from './types.js';

let instance: Repositories | null = null;

export function getRepositories(): Repositories {
  if (!instance) {
    instance =
      env.DB_DRIVER === 'postgres' ? createPostgresRepositories() : createMemoryRepositories();
    logger.info({ driver: instance.driver }, 'Storage driver initialised');
  }
  return instance;
}

/** Test helper — swap in a fresh in-memory store between test files. */
export function resetRepositories(): void {
  resetMemoryStore();
  instance = null;
}

export async function closeRepositories(): Promise<void> {
  if (instance) {
    await instance.close();
    instance = null;
  }
}

export type { Repositories };
