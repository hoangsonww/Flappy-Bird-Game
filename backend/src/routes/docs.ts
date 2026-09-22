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

const FAVICON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#0f172a"/>
  <path d="M13 31h13v-9h18v6h8v14h-8v6H26v-8H13z" fill="#facc15"/>
  <path d="M44 28h8v8h-8z" fill="#fff"/>
  <path d="M49 30h3v5h-3z" fill="#0f172a"/>
  <path d="M51 37h11v6H51z" fill="#f97316"/>
</svg>`;

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
    <meta name="theme-color" content="#f7f8f2" />
    <meta name="description" content="Interactive reference for the optional Flappy Bird accounts, scores and leaderboard API." />
    <title>Flappy Bird API — Swagger UI</title>
    <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
    <link rel="stylesheet" href="/docs/assets/swagger-ui.css" />
    <style>
      :root {
        color-scheme: light only;
        --ink: #172a2d;
        --muted: #617174;
        --paper: #f7f8f2;
        --surface: #fff;
        --line: #dce5df;
        --teal: #147b73;
        --teal-soft: #e4f2ed;
        --yellow: #e8b936;
      }
      * { box-sizing: border-box; }
      html { scroll-behavior: smooth; background: var(--paper); }
      body {
        margin: 0;
        min-width: 320px;
        background: radial-gradient(circle at 92% -8%, rgba(232,185,54,.18), transparent 25rem), var(--paper);
        color: var(--ink);
        font-family: "Avenir Next", Avenir, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      .skip-link {
        position: fixed; top: .75rem; left: .75rem; z-index: 10;
        transform: translateY(-160%); border-radius: .5rem;
        background: var(--ink); color: #fff; padding: .7rem 1rem;
      }
      .skip-link:focus { transform: translateY(0); }
      .api-masthead {
        border-top: .35rem solid var(--yellow);
        border-bottom: 1px solid var(--line);
        background: rgba(255,255,255,.88);
        backdrop-filter: blur(14px);
      }
      .api-masthead__inner {
        width: min(100% - 2rem, 74rem); margin: 0 auto;
        padding: 2.75rem 0 2.9rem;
      }
      .api-kicker {
        display: inline-flex; align-items: center; gap: .55rem; margin-bottom: 1rem;
        color: var(--teal); font: 700 .72rem/1 ui-monospace, SFMono-Regular, Menlo, monospace;
        letter-spacing: .14em; text-transform: uppercase;
      }
      .api-kicker::before {
        width: .55rem; height: .55rem; border-radius: 50%; background: #27a66f;
        box-shadow: 0 0 0 .28rem rgba(39,166,111,.12); content: "";
      }
      .api-title-row { display: flex; align-items: center; gap: 1rem; }
      .api-mark { width: 3.5rem; height: 3.5rem; flex: 0 0 auto; filter: drop-shadow(0 .4rem .65rem rgba(23,42,45,.12)); }
      .api-masthead h1 {
        margin: 0; color: var(--ink); font-size: clamp(2.25rem, 5vw, 4.5rem);
        line-height: .96; letter-spacing: -.055em; text-wrap: balance;
      }
      .api-masthead p {
        max-width: 44rem; margin: 1.25rem 0 0; color: var(--muted);
        font-size: clamp(1rem, 2vw, 1.15rem); line-height: 1.65; text-wrap: pretty;
      }
      .api-links { display: flex; flex-wrap: wrap; gap: .65rem; margin-top: 1.6rem; }
      .api-links a {
        border: 1px solid var(--line); border-radius: .55rem; background: var(--surface);
        color: var(--ink); padding: .65rem .85rem; font-size: .82rem; font-weight: 700;
        text-decoration: none; transition: border-color .2s ease, color .2s ease, transform .2s ease;
      }
      .api-links a:hover { transform: translateY(-1px); border-color: var(--teal); color: var(--teal); }
      .api-links a:active { transform: translateY(0); }
      .api-links a:focus-visible { outline: 3px solid rgba(20,123,115,.25); outline-offset: 2px; }
      #api-reference { min-height: 60vh; }
      .topbar, [aria-label="Switch to dark mode"], [aria-label="Switch to light mode"] { display: none !important; }
      .swagger-ui { color: var(--ink); font-family: inherit; }
      .swagger-ui .wrapper { max-width: 74rem; padding: 0 1rem; }
      .swagger-ui .info { margin: 3rem 0 2.5rem; }
      .swagger-ui .info .title, .swagger-ui .info h1, .swagger-ui .info h2,
      .swagger-ui .info h3, .swagger-ui .info h4, .swagger-ui .opblock-tag,
      .swagger-ui .opblock-tag small, .swagger-ui .model-title, .swagger-ui .model {
        color: var(--ink); font-family: inherit;
      }
      .swagger-ui .info .title { font-size: clamp(1.8rem,3vw,2.6rem); letter-spacing: -.035em; }
      .swagger-ui .info p, .swagger-ui .info li, .swagger-ui .info table {
        color: #45575a; font-size: .95rem; line-height: 1.7;
      }
      .swagger-ui .info .description { max-width: 64rem; }
      .swagger-ui .info a { color: var(--teal); }
      .swagger-ui .info code, .swagger-ui .markdown code {
        border-radius: .3rem; background: #edf2ef; color: #31524f; padding: .12rem .3rem;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      }
      .swagger-ui .info pre, .swagger-ui .markdown pre {
        border: 1px solid #263d3f; border-radius: .75rem; background: #1b3032; box-shadow: none;
      }
      .swagger-ui .info table { overflow: hidden; border: 1px solid var(--line); border-radius: .6rem; background: #fff; }
      .swagger-ui .info table thead tr { background: var(--teal-soft); }
      .swagger-ui .info table td, .swagger-ui .info table th { border-color: var(--line); padding: .7rem .8rem; }
      .swagger-ui .scheme-container {
        margin: 0 0 2rem; padding: 1rem 1.1rem; border: 1px solid var(--line);
        border-radius: .8rem; background: rgba(255,255,255,.92); box-shadow: 0 .75rem 2rem rgba(35,71,66,.06);
      }
      .swagger-ui select, .swagger-ui input[type="text"] {
        border-color: #bdccc5; border-radius: .5rem; background-color: #fff; color: var(--ink);
      }
      .swagger-ui .btn {
        border-color: var(--teal); border-radius: .45rem; box-shadow: none; color: var(--teal);
        font-family: inherit; transition: background-color .2s ease, color .2s ease, transform .2s ease;
      }
      .swagger-ui .btn:hover { background: var(--teal); color: #fff; }
      .swagger-ui .btn:active { transform: translateY(1px); }
      .swagger-ui .filter-container { margin-bottom: 1.75rem; }
      .swagger-ui .filter .operation-filter-input { padding: .7rem .8rem; }
      .swagger-ui .opblock-tag {
        margin: 0 0 .75rem; border-bottom: 1px solid var(--line);
        font-size: 1.35rem; letter-spacing: -.02em;
      }
      .swagger-ui .opblock-tag:hover { background: rgba(228,242,237,.55); }
      .swagger-ui .opblock {
        overflow: hidden; margin: 0 0 .65rem; border-width: 1px; border-radius: .65rem;
        background: var(--surface); box-shadow: 0 .3rem 1rem rgba(35,71,66,.045);
      }
      .swagger-ui .opblock .opblock-summary { min-height: 3.25rem; padding: .35rem .7rem; }
      .swagger-ui .opblock .opblock-summary-method { border-radius: .38rem; box-shadow: none; }
      .swagger-ui .opblock .opblock-summary-path, .swagger-ui .opblock .opblock-summary-description { color: var(--ink); }
      .swagger-ui section.models {
        overflow: hidden; margin: 2.5rem 0 4rem; border: 1px solid var(--line);
        border-radius: .8rem; background: #fff;
      }
      .swagger-ui section.models h4 { border-color: var(--line); color: var(--ink); }
      .swagger-ui .model-container { background: #f2f5f2; }
      .swagger-ui .json-schema-2020-12-accordion,
      .swagger-ui .json-schema-2020-12-expand-deep-button {
        appearance: none;
        -webkit-appearance: none;
        background: transparent;
        color: inherit;
        box-shadow: none;
      }
      .api-footer {
        border-top: 1px solid var(--line); color: var(--muted); padding: 1.4rem 1rem 2.2rem;
        text-align: center; font-size: .78rem;
      }
      @media (max-width: 620px) {
        .api-masthead__inner { width: min(100% - 1.4rem,74rem); padding: 2rem 0 2.2rem; }
        .api-mark { width: 2.8rem; height: 2.8rem; }
        .swagger-ui .wrapper { padding: 0 .7rem; }
        .swagger-ui .info { margin-top: 2rem; }
        .swagger-ui .opblock .opblock-summary-description { display: none; }
      }
      @media (prefers-reduced-motion: reduce) {
        html { scroll-behavior: auto; }
        *, *::before, *::after { transition-duration: .01ms !important; }
      }
    </style>
  </head>
  <body>
    <a class="skip-link" href="#api-reference">Skip to API reference</a>
    <header class="api-masthead">
      <div class="api-masthead__inner">
        <div class="api-kicker">Local service online</div>
        <div class="api-title-row">
          <img class="api-mark" src="/favicon.svg" alt="" />
          <h1>Flappy Bird API</h1>
        </div>
        <p>Accounts, score sync, achievements and leaderboards for the iOS game. The backend is optional; the game remains fully playable offline.</p>
        <nav class="api-links" aria-label="API resources">
          <a href="/healthz">Health status</a>
          <a href="/openapi.json">OpenAPI JSON</a>
          <a href="https://github.com/hoangsonww/Flappy-Bird-Game">Source repository</a>
        </nav>
      </div>
    </header>
    <main id="api-reference"><div id="swagger-ui"></div></main>
    <footer class="api-footer">Flappy Bird Backend · API v1 · Optional by design</footer>
    <script src="/docs/assets/swagger-ui-bundle.js" crossorigin></script>
    <script>
      window.ui = SwaggerUIBundle({
        url: '/openapi.json',
        dom_id: '#swagger-ui',
        deepLinking: true,
        persistAuthorization: true,
        displayRequestDuration: true,
        filter: true,
        tryItOutEnabled: true,
        defaultModelsExpandDepth: 1,
        presets: [SwaggerUIBundle.presets.apis],
        plugins: [SwaggerUIBundle.plugins.DownloadUrl],
        layout: 'BaseLayout',
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
    <redoc spec-url="/openapi.json" hide-download-button="false"></redoc>
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

docsRouter.get('/favicon.svg', (_req: Request, res: Response) => {
  res.type('image/svg+xml').send(FAVICON_SVG);
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
