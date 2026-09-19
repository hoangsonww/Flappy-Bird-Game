/**
 * Interactive API documentation.
 *
 * | Path            | What it serves                                              |
 * |-----------------|-------------------------------------------------------------|
 * | `/docs`         | Swagger UI (assets bundled locally, works fully offline)     |
 * | `/redoc`        | ReDoc single-page reference (loads ReDoc from a CDN)          |
 * | `/openapi.json` | The specification as JSON                                    |
 * | `/openapi.yaml` | The specification as YAML (source of truth)                  |
 */
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express, { Router, type Request, type Response } from 'express';
import { parse } from 'yaml';
import { env } from '../config/env.js';
import { logger } from '../config/logger.js';
import { forbidden, notFound } from '../utils/errors.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const specPath = path.resolve(here, '..', '..', 'openapi', 'openapi.yaml');

interface LoadedSpec {
  yaml: string;
  json: Record<string, unknown>;
}

let cached: LoadedSpec | null = null;

/** Read + parse the spec once, then serve from memory (re-read in dev). */
export function loadSpec(): LoadedSpec {
  if (cached && !env.isDevelopment) return cached;
  const yaml = readFileSync(specPath, 'utf8');
  const json = parse(yaml) as Record<string, unknown>;
  const servers = [
    { url: env.publicUrl, description: 'This server' },
    { url: 'http://localhost:4000', description: 'Local development' },
  ];
  cached = { yaml, json: { ...json, servers } };
  return cached;
}

const require = createRequire(import.meta.url);

/** Locate the bundled Swagger UI assets so `/docs` works without internet access. */
function swaggerUiDistPath(): string | null {
  const candidates: Array<() => string> = [
    () => path.dirname(require.resolve('swagger-ui-dist/package.json')),
    () => path.dirname(require.resolve('swagger-ui-dist/swagger-ui.css')),
    () => path.resolve(here, '..', '..', 'node_modules', 'swagger-ui-dist'),
    () => path.resolve(here, '..', '..', '..', 'node_modules', 'swagger-ui-dist'),
  ];

  for (const candidate of candidates) {
    try {
      const dir = candidate();
      if (existsSync(path.join(dir, 'swagger-ui-bundle.js'))) return dir;
    } catch {
      // try the next strategy
    }
  }
  return null;
}

const SWAGGER_PAGE = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Flappy Bird API — Swagger UI</title>
    <link rel="stylesheet" href="./assets/swagger-ui.css" />
    <style>
      body { margin: 0; background: #0f172a; }
      .topbar { display: none; }
      .swagger-ui .info { margin: 24px 0; }
    </style>
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="./assets/swagger-ui-bundle.js" crossorigin></script>
    <script src="./assets/swagger-ui-standalone-preset.js" crossorigin></script>
    <script>
      window.ui = SwaggerUIBundle({
        url: '../openapi.json',
        dom_id: '#swagger-ui',
        deepLinking: true,
        persistAuthorization: true,
        displayRequestDuration: true,
        filter: true,
        tryItOutEnabled: true,
        defaultModelsExpandDepth: 1,
        presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
        plugins: [SwaggerUIBundle.plugins.DownloadUrl],
        layout: 'StandaloneLayout',
      });
    </script>
  </body>
</html>`;

const REDOC_PAGE = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Flappy Bird API — Reference</title>
    <style>body { margin: 0; }</style>
  </head>
  <body>
    <redoc spec-url="../openapi.json" hide-download-button="false"></redoc>
    <script src="https://cdn.jsdelivr.net/npm/redoc@2.2.0/bundles/redoc.standalone.js"></script>
  </body>
</html>`;

export const docsRouter = Router();

docsRouter.use((_req, _res, next) => {
  if (!env.ENABLE_DOCS) {
    next(forbidden('API documentation is disabled on this server (set ENABLE_DOCS=true)'));
    return;
  }
  next();
});

docsRouter.get('/openapi.json', (_req: Request, res: Response) => {
  res.json(loadSpec().json);
});

docsRouter.get('/openapi.yaml', (_req: Request, res: Response) => {
  res.type('application/yaml').send(loadSpec().yaml);
});

const assetsDir = swaggerUiDistPath();
if (assetsDir) {
  docsRouter.use('/docs/assets', express.static(assetsDir, { maxAge: '1h', index: false }));
} else {
  logger.warn('swagger-ui-dist not found; /docs will report 404 until dependencies are installed');
}

docsRouter.get('/docs', (_req: Request, res: Response) => {
  if (!assetsDir) throw notFound('Swagger UI assets are not installed (run npm install)');
  res.type('html').send(SWAGGER_PAGE);
});

docsRouter.get('/redoc', (_req: Request, res: Response) => {
  res.type('html').send(REDOC_PAGE);
});
