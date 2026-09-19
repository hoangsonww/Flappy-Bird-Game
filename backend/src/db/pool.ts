import { Pool, type PoolClient, type QueryResult, type QueryResultRow } from 'pg';
import { env } from '../config/env.js';
import { logger } from '../config/logger.js';

let pool: Pool | null = null;

/** Lazily create the shared connection pool. */
export function getPool(): Pool {
  if (!pool) {
    pool = new Pool({
      connectionString: env.DATABASE_URL,
      max: env.DATABASE_POOL_MAX,
      ssl: env.DATABASE_SSL ? { rejectUnauthorized: false } : undefined,
      application_name: 'flappy-bird-backend',
    });

    pool.on('error', (error) => {
      logger.error({ err: error }, 'Unexpected idle Postgres client error');
    });
  }
  return pool;
}

export async function query<T extends QueryResultRow = QueryResultRow>(
  sql: string,
  params: ReadonlyArray<unknown> = [],
): Promise<QueryResult<T>> {
  const started = process.hrtime.bigint();
  try {
    return await getPool().query<T>(sql, params as unknown[]);
  } finally {
    const durationMs = Number(process.hrtime.bigint() - started) / 1e6;
    if (durationMs > 250) {
      logger.warn({ durationMs: Math.round(durationMs), sql: sql.slice(0, 160) }, 'Slow query');
    }
  }
}

/** Run a callback inside a transaction, rolling back on any thrown error. */
export async function transaction<T>(handler: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    const result = await handler(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

export async function closePool(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}

/** Wait for Postgres to accept connections — used by `make up` and the container entrypoint. */
export async function waitForDatabase(attempts = 30, delayMs = 1_000): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      await query('SELECT 1');
      return;
    } catch (error) {
      if (attempt === attempts) throw error;
      logger.warn({ attempt, attempts }, 'Waiting for Postgres…');
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
}
