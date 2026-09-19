/**
 * Environment configuration.
 *
 * Every setting has a sane default so that `npm run dev` works with zero
 * configuration (in-memory driver, ephemeral JWT secrets). Production mode is
 * strict: secrets and a real database URL must be supplied explicitly.
 */
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { z } from 'zod';

const here = path.dirname(fileURLToPath(import.meta.url));
// src/config -> backend/
const backendRoot = path.resolve(here, '..', '..');

dotenv.config({ path: path.join(backendRoot, '.env') });
dotenv.config({ path: path.resolve(backendRoot, '..', '.env') });

const booleanish = z
  .union([z.boolean(), z.string()])
  .transform((value) =>
    typeof value === 'boolean' ? value : ['1', 'true', 'yes', 'on'].includes(value.toLowerCase()),
  );

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(0).max(65535).default(4000),
  HOST: z.string().default('0.0.0.0'),
  PUBLIC_URL: z.string().default(''),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  TRUST_PROXY: booleanish.default(false),

  DB_DRIVER: z.enum(['postgres', 'memory']).default('memory'),
  DATABASE_URL: z.string().default('postgres://flappy:flappy@localhost:5432/flappybird'),
  DATABASE_SSL: booleanish.default(false),
  DATABASE_POOL_MAX: z.coerce.number().int().min(1).max(200).default(10),
  DATABASE_AUTO_MIGRATE: booleanish.default(true),

  JWT_ACCESS_SECRET: z.string().default(''),
  JWT_REFRESH_SECRET: z.string().default(''),
  JWT_ISSUER: z.string().default('flappy-bird-backend'),
  ACCESS_TOKEN_TTL: z.string().default('15m'),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(30),
  BCRYPT_ROUNDS: z.coerce.number().int().min(4).max(15).default(11),

  CORS_ORIGINS: z.string().default('*'),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().min(1000).default(60_000),
  RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(240),
  AUTH_RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(20),
  SUBMIT_RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(60),

  ADMIN_TOKEN: z.string().default(''),
  RUN_SIGNING_SECRET: z.string().default(''),
  REQUIRE_SIGNED_RUNS: booleanish.default(false),

  ENABLE_DOCS: booleanish.default(true),
  ENABLE_METRICS: booleanish.default(true),
  ENABLE_SSE: booleanish.default(true),
  ENABLE_GUEST_ACCOUNTS: booleanish.default(true),

  MAX_SCORE: z.coerce.number().int().min(1).default(100_000),
  MAX_PIPES_PER_SECOND: z.coerce.number().min(0.1).default(1.6),
  LEADERBOARD_PAGE_MAX: z.coerce.number().int().min(1).max(500).default(100),
});

export type RawEnv = z.infer<typeof schema>;

function ephemeralSecret(label: string, nodeEnv: string): string {
  if (nodeEnv === 'production') {
    throw new Error(`${label} must be set in production. Generate one with: openssl rand -hex 48`);
  }
  return randomBytes(48).toString('hex');
}

function parse(): RawEnv & {
  isProduction: boolean;
  isTest: boolean;
  isDevelopment: boolean;
  corsOrigins: string[] | '*';
  publicUrl: string;
  generatedSecrets: string[];
} {
  const parsed = schema.safeParse(process.env);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((issue) => `  - ${issue.path.join('.') || '(root)'}: ${issue.message}`)
      .join('\n');
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }

  const env = parsed.data;
  const generatedSecrets: string[] = [];

  if (!env.JWT_ACCESS_SECRET) {
    env.JWT_ACCESS_SECRET = ephemeralSecret('JWT_ACCESS_SECRET', env.NODE_ENV);
    generatedSecrets.push('JWT_ACCESS_SECRET');
  }
  if (!env.JWT_REFRESH_SECRET) {
    env.JWT_REFRESH_SECRET = ephemeralSecret('JWT_REFRESH_SECRET', env.NODE_ENV);
    generatedSecrets.push('JWT_REFRESH_SECRET');
  }
  if (env.NODE_ENV === 'production' && env.DB_DRIVER === 'memory') {
    throw new Error('DB_DRIVER=memory is not allowed in production. Use DB_DRIVER=postgres.');
  }
  if (env.REQUIRE_SIGNED_RUNS && !env.RUN_SIGNING_SECRET) {
    throw new Error('REQUIRE_SIGNED_RUNS=true requires RUN_SIGNING_SECRET to be set.');
  }

  const corsOrigins =
    env.CORS_ORIGINS.trim() === '*'
      ? ('*' as const)
      : env.CORS_ORIGINS.split(',')
          .map((origin) => origin.trim())
          .filter(Boolean);

  return {
    ...env,
    isProduction: env.NODE_ENV === 'production',
    isTest: env.NODE_ENV === 'test',
    isDevelopment: env.NODE_ENV === 'development',
    corsOrigins,
    publicUrl: env.PUBLIC_URL || `http://localhost:${env.PORT}`,
    generatedSecrets,
  };
}

export const env = parse();
export type Env = typeof env;
