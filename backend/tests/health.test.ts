import { beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { freshApp } from './helpers.js';

describe('operations endpoints', () => {
  let app: Express;

  beforeEach(async () => {
    app = await freshApp();
  });

  it('reports the service identity at the root', async () => {
    const response = await request(app).get('/').expect(200);
    expect(response.body).toMatchObject({
      service: 'flappy-bird-backend',
      protocol: 'flappy-bird/1',
    });
  });

  it('answers liveness without touching storage', async () => {
    const response = await request(app).get('/livez').expect(200);
    expect(response.body.status).toBe('alive');
  });

  it('answers readiness with the active driver', async () => {
    const response = await request(app).get('/readyz').expect(200);
    expect(response.body.status).toBe('ready');
    expect(['memory', 'postgres']).toContain(response.body.driver);
  });

  it('answers a full health summary', async () => {
    const response = await request(app).get('/healthz').expect(200);
    expect(response.body).toMatchObject({ status: 'ok', database: 'ok' });
  });

  it('exposes prometheus metrics including custom counters', async () => {
    const response = await request(app).get('/metrics').expect(200);
    expect(response.text).toContain('flappy_scores_submitted_total');
    expect(response.text).toContain('http_request_duration_seconds');
  });

  it('advertises the discovery handshake the game depends on', async () => {
    const response = await request(app).get('/v1/meta/config').expect(200);
    expect(response.body.protocol).toBe('flappy-bird/1');
    expect(response.body.capabilities).toContain('scores.submit');
    expect(response.body.gameModes).toContain('classic');
  });

  it('returns a structured 404 with a request id', async () => {
    const response = await request(app).get('/v1/nope').expect(404);
    expect(response.body.error.code).toBe('not_found');
    expect(response.body.error.requestId).toBeTruthy();
    expect(response.headers['x-request-id']).toBe(response.body.error.requestId);
  });

  it('echoes an inbound request id', async () => {
    const response = await request(app).get('/livez').set('X-Request-Id', 'trace-me').expect(200);
    expect(response.headers['x-request-id']).toBe('trace-me');
  });
});
