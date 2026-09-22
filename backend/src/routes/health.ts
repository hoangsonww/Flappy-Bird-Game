/** Liveness, readiness and Prometheus endpoints (all outside `/v1`). */
import { Router, type Request, type Response } from 'express';
import { env } from '../config/env.js';
import { API_VERSION } from '../config/constants.js';
import { getRepositories } from '../repositories/index.js';
import { registry } from '../middleware/metrics.js';
import { forbidden } from '../utils/errors.js';

export const healthRouter = Router();

const bootedAt = Date.now();

/** Process is alive — never touches the database. */
healthRouter.get('/livez', (_req: Request, res: Response) => {
  res.json({ status: 'alive', uptimeSeconds: Math.round(process.uptime()) });
});

/** Dependencies are reachable — this is what orchestrators should poll. */
healthRouter.get('/readyz', async (_req: Request, res: Response) => {
  try {
    await getRepositories().ping();
    res.json({ status: 'ready', driver: getRepositories().driver });
  } catch (error) {
    res.status(503).json({
      status: 'degraded',
      driver: getRepositories().driver,
      error: (error as Error).message,
    });
  }
});

/** Human-friendly summary used by `make health` and the Docker healthcheck. */
healthRouter.get('/healthz', async (_req: Request, res: Response) => {
  let database = 'ok';
  try {
    await getRepositories().ping();
  } catch (error) {
    database = `error: ${(error as Error).message}`;
  }

  const healthy = database === 'ok';
  res.status(healthy ? 200 : 503).json({
    status: healthy ? 'ok' : 'degraded',
    service: 'flappy-bird-backend',
    apiVersion: API_VERSION,
    environment: env.NODE_ENV,
    driver: getRepositories().driver,
    database,
    uptimeSeconds: Math.round((Date.now() - bootedAt) / 1000),
    timestamp: new Date().toISOString(),
  });
});

healthRouter.get('/metrics', async (_req: Request, res: Response) => {
  if (!env.ENABLE_METRICS) throw forbidden('Metrics are disabled on this server');
  res.setHeader('Content-Type', registry.contentType);
  res.send(await registry.metrics());
});
