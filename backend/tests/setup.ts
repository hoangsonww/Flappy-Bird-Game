/**
 * Vitest global setup.
 *
 * The suite runs against either storage driver:
 *
 *   npm test                      # in-memory (default, no infrastructure)
 *   DB_DRIVER=postgres npm test   # real schema; needs DATABASE_URL
 *
 * Running both in CI is what keeps the two drivers behaviourally identical.
 */
import { env } from '../src/config/env.js';

export default async function setup(): Promise<void> {
  if (env.DB_DRIVER !== 'postgres') return;
  const { up } = await import('../src/db/migrate.js');
  await up();
}
