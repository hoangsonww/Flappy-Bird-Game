import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    env: {
      NODE_ENV: 'test',
      DB_DRIVER: process.env.DB_DRIVER ?? 'memory',
      ADMIN_TOKEN: 'test-admin-token',
      RUN_SIGNING_SECRET: 'test-run-signing-secret',
      LOG_LEVEL: 'silent',
    },
    globals: false,
    include: ['tests/**/*.test.ts'],
    globalSetup: ['tests/setup.ts'],
    reporters: ['default'],
    pool: 'forks',
    // Every test file truncates the database between tests, so against a shared
    // Postgres instance the files must not run concurrently. The in-memory
    // driver is per-process and stays fully parallel.
    fileParallelism: process.env.DB_DRIVER !== 'postgres',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov', 'html'],
      reportsDirectory: './coverage',
      include: ['src/**/*.ts'],
      exclude: ['src/server.ts', 'src/db/migrate.ts', 'src/db/seed.ts', 'src/types/**'],
    },
  },
});
