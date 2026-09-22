/** Express application wiring. Kept free of side effects so tests can import it. */
import compression from 'compression';
import cors from 'cors';
import express, { type Express, type Request, type Response } from 'express';
import helmet from 'helmet';
import pinoHttp from 'pino-http';
import { env } from './config/env.js';
import { logger } from './config/logger.js';
import { errorHandler, notFoundHandler } from './middleware/error.js';
import { metricsMiddleware } from './middleware/metrics.js';
import { requestContext } from './middleware/requestContext.js';
import { docsRouter } from './routes/docs.js';
import { healthRouter } from './routes/health.js';
import { v1Router } from './routes/index.js';

export function createApp(): Express {
  const app = express();

  if (env.TRUST_PROXY) app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.set('json spaces', env.isProduction ? 0 : 2);

  app.use(requestContext);
  app.use(
    helmet({
      // Swagger UI and ReDoc need inline styles/scripts; the API itself serves JSON.
      contentSecurityPolicy: false,
      crossOriginEmbedderPolicy: false,
    }),
  );
  app.use(
    cors({
      origin: env.corsOrigins === '*' ? true : env.corsOrigins,
      credentials: true,
      exposedHeaders: ['X-Request-Id', 'RateLimit-Limit', 'RateLimit-Remaining', 'RateLimit-Reset'],
    }),
  );
  app.use(compression());
  app.use(express.json({ limit: '64kb' }));
  app.use(express.urlencoded({ extended: false, limit: '64kb' }));

  if (!env.isTest) {
    app.use(
      pinoHttp({
        logger,
        genReqId: (req) => (req as Request).requestId,
        autoLogging: { ignore: (req) => req.url === '/metrics' || req.url === '/livez' },
        customLogLevel: (_req, res, error) => {
          if (error || res.statusCode >= 500) return 'error';
          if (res.statusCode >= 400) return 'warn';
          return 'info';
        },
      }),
    );
  }

  if (env.ENABLE_METRICS) app.use(metricsMiddleware);

  // Send human visitors straight to the interactive API documentation. The iOS
  // client uses /v1/meta/config for its machine-readable discovery handshake.
  app.get('/', (_req: Request, res: Response) => {
    res.redirect(302, '/docs');
  });

  app.use(healthRouter);
  app.use(docsRouter);
  app.use('/v1', v1Router);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
