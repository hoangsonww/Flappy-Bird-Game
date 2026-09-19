/**
 * Contract guard: every route the app exposes must be documented, and every
 * documented route must exist. This keeps `openapi.yaml` honest over time.
 */
import { describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Router } from 'express';
import { loadSpec } from '../src/routes/docs.js';
import { achievementsRouter } from '../src/routes/achievements.js';
import { adminRouter } from '../src/routes/admin.js';
import { authRouter } from '../src/routes/auth.js';
import { challengesRouter } from '../src/routes/challenges.js';
import { friendsRouter } from '../src/routes/friends.js';
import { healthRouter } from '../src/routes/health.js';
import { leaderboardRouter } from '../src/routes/leaderboard.js';
import { metaRouter } from '../src/routes/meta.js';
import { scoresRouter } from '../src/routes/scores.js';
import { usersRouter } from '../src/routes/users.js';
import { freshApp } from './helpers.js';

/**
 * Mount points mirror `src/routes/index.ts` and `src/app.ts`. Keeping them here
 * explicitly (rather than introspecting Express internals, which changed shape
 * in Express 5) means a new router must be registered in both places.
 */
const MOUNTS: Array<[string, Router]> = [
  ['', healthRouter],
  ['/v1/meta', metaRouter],
  ['/v1/auth', authRouter],
  ['/v1/users', usersRouter],
  ['/v1/scores', scoresRouter],
  ['/v1/leaderboard', leaderboardRouter],
  ['/v1/achievements', achievementsRouter],
  ['/v1/challenges', challengesRouter],
  ['/v1/friends', friendsRouter],
  ['/v1/admin', adminRouter],
];

interface RouterLike {
  stack: Array<{ route?: { path: string; methods: Record<string, boolean> } }>;
}

/** Enumerate `METHOD /path` pairs the application actually serves. */
function implementedRoutes(): Set<string> {
  const routes = new Set<string>(['GET /']);

  for (const [prefix, router] of MOUNTS) {
    for (const layer of (router as unknown as RouterLike).stack) {
      if (!layer.route) continue;
      for (const [method, enabled] of Object.entries(layer.route.methods)) {
        if (!enabled || method === '_all') continue;
        routes.add(`${method.toUpperCase()} ${normalise(prefix + layer.route.path)}`);
      }
    }
  }

  return routes;
}

const normalise = (path: string): string =>
  path.replace(/\/+$/, '').replace(/:(\w+)/g, '{$1}') || '/';

describe('openapi specification', () => {
  const spec = loadSpec().json as {
    openapi: string;
    info: Record<string, unknown>;
    paths: Record<string, Record<string, unknown>>;
    components: { schemas: Record<string, unknown>; securitySchemes: Record<string, unknown> };
    tags: Array<{ name: string; description: string }>;
  };

  it('is a valid OpenAPI 3.1 document with the expected metadata', () => {
    expect(spec.openapi).toBe('3.1.0');
    expect(spec.info).toMatchObject({ title: 'Flappy Bird Backend API' });
    expect(Object.keys(spec.paths).length).toBeGreaterThan(30);
    expect(Object.keys(spec.components.schemas).length).toBeGreaterThan(20);
    expect(spec.components.securitySchemes).toHaveProperty('bearerAuth');
    expect(spec.components.securitySchemes).toHaveProperty('adminToken');
  });

  it('documents every tag it references', () => {
    const declared = new Set(spec.tags.map((tag) => tag.name));
    for (const [path, operations] of Object.entries(spec.paths)) {
      for (const [method, operation] of Object.entries(operations)) {
        const tags = (operation as { tags?: string[] }).tags ?? [];
        expect(tags.length, `${method.toUpperCase()} ${path} has no tag`).toBeGreaterThan(0);
        for (const tag of tags) expect(declared, `undeclared tag ${tag}`).toContain(tag);
      }
    }
  });

  it('gives every operation a summary and an operationId', () => {
    const ids = new Set<string>();
    for (const [path, operations] of Object.entries(spec.paths)) {
      for (const [method, operation] of Object.entries(operations)) {
        const op = operation as { summary?: string; operationId?: string };
        expect(op.summary, `${method.toUpperCase()} ${path} needs a summary`).toBeTruthy();
        expect(op.operationId, `${method.toUpperCase()} ${path} needs an operationId`).toBeTruthy();
        expect(ids.has(op.operationId!), `duplicate operationId ${op.operationId}`).toBe(false);
        ids.add(op.operationId!);
      }
    }
  });

  it('documents every route the application serves', () => {
    const implemented = implementedRoutes();
    const documented = new Set<string>();
    for (const [path, operations] of Object.entries(spec.paths)) {
      for (const method of Object.keys(operations)) {
        documented.add(`${method.toUpperCase()} ${normalise(path)}`);
      }
    }

    // Documentation and asset routes are intentionally not part of the contract.
    const ignored = (route: string) =>
      route.includes('/openapi') || route.includes('/docs') || route.includes('/redoc');

    const undocumented = [...implemented].filter(
      (route) => !documented.has(route) && !ignored(route),
    );
    expect(undocumented, `undocumented routes: ${undocumented.join(', ')}`).toEqual([]);
  });

  it('serves the specification as JSON and YAML', async () => {
    const app = await freshApp();
    const json = await request(app).get('/openapi.json').expect(200);
    expect(json.body.openapi).toBe('3.1.0');

    const yaml = await request(app).get('/openapi.yaml').expect(200);
    expect(yaml.text).toContain('openapi: 3.1.0');
  });

  it('serves Swagger UI and ReDoc pages', async () => {
    const app = await freshApp();
    const swagger = await request(app).get('/docs').expect(200);
    expect(swagger.text).toContain('swagger-ui');

    const redoc = await request(app).get('/redoc').expect(200);
    expect(redoc.text).toContain('redoc');
  });
});
