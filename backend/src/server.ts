#!/usr/bin/env node
/**
 * Process entry point.
 *
 * Responsibilities beyond `createApp()`:
 *  - optionally run migrations on boot (`DATABASE_AUTO_MIGRATE`, Postgres only);
 *  - print a readable startup banner;
 *  - shut down cleanly on SIGINT/SIGTERM so `docker compose down` is instant.
 */
import { createApp } from './app.js';
import { env } from './config/env.js';
import { logger } from './config/logger.js';
import { closeRepositories, getRepositories } from './repositories/index.js';

async function bootstrap(): Promise<void> {
  if (env.generatedSecrets.length > 0) {
    logger.warn(
      { generated: env.generatedSecrets },
      'Using ephemeral JWT secrets — tokens will be invalidated on restart. Set them in .env for stable sessions.',
    );
  }

  const repos = getRepositories();

  if (repos.driver === 'postgres' && env.DATABASE_AUTO_MIGRATE) {
    const { up } = await import('./db/migrate.js');
    const { applied } = await up();
    logger.info({ applied: applied.length }, 'Database migrations checked');
  }

  const app = createApp();
  const server = app.listen(env.PORT, env.HOST, () => {
    banner();
  });

  server.keepAliveTimeout = 65_000;
  server.headersTimeout = 66_000;

  const shutdown = (signal: string) => {
    logger.info({ signal }, 'Shutting down');
    server.close(async () => {
      await closeRepositories();
      process.exit(0);
    });
    // Force-exit if connections refuse to drain.
    setTimeout(() => process.exit(1), 10_000).unref();
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('unhandledRejection', (reason) => {
    logger.error({ err: reason }, 'Unhandled promise rejection');
  });
}

function banner(): void {
  const lines = [
    '',
    '  🐦  Flappy Bird backend is up',
    '  ──────────────────────────────────────────────',
    `  URL        ${env.publicUrl}`,
    `  Env        ${env.NODE_ENV}`,
    `  Storage    ${getRepositories().driver}`,
    `  Docs       ${env.ENABLE_DOCS ? `${env.publicUrl}/docs` : 'disabled'}`,
    `  Health     ${env.publicUrl}/healthz`,
    `  Metrics    ${env.ENABLE_METRICS ? `${env.publicUrl}/metrics` : 'disabled'}`,
    '  ──────────────────────────────────────────────',
    '  The iOS game auto-detects this server on launch.',
    '',
  ];
  console.log(lines.join('\n'));
}

bootstrap().catch((error) => {
  logger.error({ err: error }, 'Failed to start server');
  console.error(`\n✖ ${(error as Error).message}\n`);
  process.exit(1);
});
