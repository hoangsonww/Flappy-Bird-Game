/** Prometheus instrumentation exposed at `GET /metrics`. */
import type { NextFunction, Request, Response } from 'express';
import { Counter, Histogram, Registry, collectDefaultMetrics } from 'prom-client';

export const registry = new Registry();
registry.setDefaultLabels({ service: 'flappy-bird-backend' });
collectDefaultMetrics({ register: registry });

const httpRequests = new Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests handled, labelled by method, route and status class.',
  labelNames: ['method', 'route', 'status'] as const,
  registers: [registry],
});

const httpDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency in seconds.',
  labelNames: ['method', 'route', 'status'] as const,
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [registry],
});

export const scoresSubmitted = new Counter({
  name: 'flappy_scores_submitted_total',
  help: 'Runs accepted by the score endpoint, labelled by mode and whether they were flagged.',
  labelNames: ['mode', 'flagged'] as const,
  registers: [registry],
});

export const accountsCreated = new Counter({
  name: 'flappy_accounts_created_total',
  help: 'Accounts created, labelled by kind (password or guest).',
  labelNames: ['kind'] as const,
  registers: [registry],
});

/** Record method/route/status/duration for every response. */
export function metricsMiddleware(req: Request, res: Response, next: NextFunction): void {
  const stopTimer = httpDuration.startTimer();
  res.on('finish', () => {
    // Prefer the matched route pattern to keep label cardinality bounded.
    const route = req.route?.path
      ? `${req.baseUrl ?? ''}${req.route.path}`
      : req.baseUrl || req.path || 'unknown';
    const labels = { method: req.method, route, status: String(res.statusCode) };
    httpRequests.inc(labels);
    stopTimer(labels);
  });
  next();
}
