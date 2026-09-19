#!/usr/bin/env tsx
/**
 * Minimal forward-only SQL migrator.
 *
 * - Files live in `backend/migrations/NNN_name.sql` and run in filename order.
 * - Applied migrations are recorded in `schema_migrations` with a SHA-256
 *   checksum, so an edited file that has already run is reported as drift
 *   instead of silently diverging.
 * - Each file runs inside its own transaction.
 *
 * Usage:
 *   npm run migrate          # apply pending migrations
 *   npm run migrate:status   # list applied / pending
 */
import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { logger } from '../config/logger.js';
import { closePool, getPool, waitForDatabase } from './pool.js';

const here = path.dirname(fileURLToPath(import.meta.url));
export const MIGRATIONS_DIR = path.resolve(here, '..', '..', 'migrations');

interface MigrationFile {
  name: string;
  sql: string;
  checksum: string;
}

async function loadMigrations(): Promise<MigrationFile[]> {
  const entries = await readdir(MIGRATIONS_DIR);
  const files = entries.filter((entry) => entry.endsWith('.sql')).sort();
  const loaded: MigrationFile[] = [];
  for (const name of files) {
    const sql = await readFile(path.join(MIGRATIONS_DIR, name), 'utf8');
    loaded.push({ name, sql, checksum: createHash('sha256').update(sql).digest('hex') });
  }
  return loaded;
}

async function ensureLedger(): Promise<void> {
  await getPool().query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name       TEXT PRIMARY KEY,
      checksum   TEXT        NOT NULL,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
}

async function appliedMigrations(): Promise<Map<string, string>> {
  const result = await getPool().query<{ name: string; checksum: string }>(
    'SELECT name, checksum FROM schema_migrations',
  );
  return new Map(result.rows.map((row) => [row.name, row.checksum]));
}

export async function up(): Promise<{ applied: string[]; skipped: string[] }> {
  await waitForDatabase();
  await ensureLedger();

  const files = await loadMigrations();
  const applied = await appliedMigrations();
  const result: { applied: string[]; skipped: string[] } = { applied: [], skipped: [] };

  for (const file of files) {
    const knownChecksum = applied.get(file.name);
    if (knownChecksum) {
      if (knownChecksum !== file.checksum) {
        throw new Error(
          `Migration drift detected in ${file.name}: the file changed after it was applied. ` +
            'Create a new migration instead of editing an applied one.',
        );
      }
      result.skipped.push(file.name);
      continue;
    }

    const client = await getPool().connect();
    try {
      await client.query('BEGIN');
      await client.query(file.sql);
      await client.query('INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)', [
        file.name,
        file.checksum,
      ]);
      await client.query('COMMIT');
      result.applied.push(file.name);
      logger.info({ migration: file.name }, 'Migration applied');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw new Error(`Migration ${file.name} failed: ${(error as Error).message}`);
    } finally {
      client.release();
    }
  }

  return result;
}

export async function status(): Promise<void> {
  await waitForDatabase();
  await ensureLedger();
  const files = await loadMigrations();
  const applied = await appliedMigrations();

  console.log('Migration status');
  console.log('────────────────');
  for (const file of files) {
    const known = applied.get(file.name);
    const state = !known ? 'pending' : known === file.checksum ? 'applied' : 'DRIFT';
    console.log(`  ${state.padEnd(8)} ${file.name}`);
  }
}

const isDirectRun =
  process.argv[1] !== undefined && import.meta.url === `file://${path.resolve(process.argv[1])}`;

if (isDirectRun) {
  const command = process.argv[2] ?? 'up';
  try {
    if (command === 'status') {
      await status();
    } else {
      const { applied, skipped } = await up();
      console.log(
        applied.length
          ? `Applied ${applied.length} migration(s): ${applied.join(', ')}`
          : `Database already up to date (${skipped.length} migration(s) applied previously).`,
      );
    }
    await closePool();
    process.exit(0);
  } catch (error) {
    console.error(`✖ ${(error as Error).message}`);
    await closePool();
    process.exit(1);
  }
}
