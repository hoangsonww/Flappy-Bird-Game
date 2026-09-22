import pino from 'pino';
import { env } from './env.js';

export const logger = pino({
  level: env.isTest ? 'silent' : env.LOG_LEVEL,
  base: { service: 'flappy-bird-backend' },
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      'req.body.password',
      'req.body.newPassword',
      'req.body.currentPassword',
      'req.body.refreshToken',
      'res.headers["set-cookie"]',
    ],
    censor: '[redacted]',
  },
  transport:
    env.isDevelopment && process.stdout.isTTY
      ? { target: 'pino/file', options: { destination: 1 } }
      : undefined,
});

export type Logger = typeof logger;
