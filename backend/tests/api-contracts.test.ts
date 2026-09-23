import type { Express } from 'express';
import request from 'supertest';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  auth,
  freshApp,
  registerUser,
  runPayload,
  submitRun,
  type TestSession,
} from './helpers.js';

describe('HTTP and API contracts', () => {
  let app: Express;
  let session: TestSession;

  beforeEach(async () => {
    app = await freshApp();
    session = await registerUser(app, 'contract_player', {
      email: 'contract@example.com',
      displayName: 'Contract Player',
    });
  });

  it('returns defensive HTTP headers and supports CORS preflight', async () => {
    const response = await request(app).get('/livez').expect(200);
    expect(response.headers['x-content-type-options']).toBe('nosniff');
    expect(response.headers['x-frame-options']).toBe('SAMEORIGIN');
    expect(response.headers['x-powered-by']).toBeUndefined();

    const preflight = await request(app)
      .options('/v1/leaderboard')
      .set('Origin', 'https://example.test')
      .set('Access-Control-Request-Method', 'GET')
      .expect(204);
    expect(preflight.headers['access-control-allow-origin']).toBe('https://example.test');
    expect(preflight.headers['access-control-allow-credentials']).toBe('true');
  });

  it('normalizes malformed JSON and oversized payload failures', async () => {
    const malformed = await request(app)
      .post('/v1/auth/login')
      .set('Content-Type', 'application/json')
      .send('{"username":')
      .expect(400);
    expect(malformed.body.error).toMatchObject({ code: 'bad_request' });
    expect(malformed.body.error.requestId).toBeTruthy();

    const oversized = await request(app)
      .post('/v1/auth/login')
      .send({ username: 'bird', password: 'x'.repeat(70_000) })
      .expect(413);
    expect(oversized.body.error.code).toBe('payload_too_large');
  });

  it('reports aggregate metadata after accepted runs', async () => {
    await submitRun(app, session, 12, { coins: 4, pipesPassed: 12, maxCombo: 4 });
    const response = await request(app).get('/v1/meta/stats').expect(200);
    expect(response.body).toMatchObject({
      players: 1,
      runsRecorded: 1,
      gamesPlayed: 1,
      pipesPassed: 12,
      coinsCollected: 4,
    });
    expect(response.body.uptimeSeconds).toBeGreaterThanOrEqual(0);
  });

  it('reports private account state and revokes all refresh sessions', async () => {
    await request(app)
      .post('/v1/auth/login')
      .send({ username: session.username, password: 'flappybird123' })
      .expect(200);

    const me = await request(app).get('/v1/auth/me').set(auth(session)).expect(200);
    expect(me.body.user).toMatchObject({
      username: session.username,
      email: 'contract@example.com',
      role: 'player',
    });
    expect(me.body.activeSessions).toBe(2);
    // The memory driver eagerly creates zeroed stats while PostgreSQL leaves
    // this nullable until the first run; both are valid API empty states.
    if (me.body.stats !== null) expect(me.body.stats.userId).toBe(session.userId);

    const logout = await request(app).post('/v1/auth/logout-all').set(auth(session)).expect(200);
    expect(logout.body.revoked).toBe(2);

    const after = await request(app).get('/v1/auth/me').set(auth(session)).expect(200);
    expect(after.body.activeSessions).toBe(0);
    await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: session.refreshToken })
      .expect(401);
  });

  it('rejects credential and guest-upgrade edge cases', async () => {
    await request(app)
      .post('/v1/auth/register')
      .send({
        username: 'another_player',
        email: 'CONTRACT@example.com',
        password: 'flappybird123',
      })
      .expect(409);

    const samePassword = await request(app)
      .patch('/v1/auth/password')
      .set(auth(session))
      .send({ currentPassword: 'flappybird123', newPassword: 'flappybird123' })
      .expect(400);
    expect(samePassword.body.error.code).toBe('bad_request');

    await request(app)
      .post('/v1/auth/upgrade')
      .set(auth(session))
      .send({ username: 'not_a_guest', password: 'anotherpassword' })
      .expect(409);
  });

  it('serves only unflagged public runs and hides banned or missing players', async () => {
    await submitRun(app, session, 8);
    await request(app)
      .post('/v1/scores')
      .set(auth(session))
      .send({ ...runPayload(80), durationMs: 100 })
      .expect(201);

    const visible = await request(app)
      .get(`/v1/users/${session.username}/scores?limit=50`)
      .expect(200);
    expect(visible.body.items.map((score: { score: number }) => score.score)).toEqual([8]);
    expect(visible.body.total).toBe(2);

    await request(app).get('/v1/users/missing_player/scores').expect(404);
    await request(app)
      .post(`/v1/admin/users/${session.username}/ban`)
      .set('X-Admin-Token', 'test-admin-token')
      .send({ reason: 'contract test' })
      .expect(200);
    await request(app).get(`/v1/users/${session.username}/scores`).expect(404);
  });

  it('returns null empty-state values and validates query boundaries', async () => {
    const best = await request(app).get('/v1/scores/me/best').set(auth(session)).expect(200);
    expect(best.body.best).toBeNull();

    const stats = await request(app).get('/v1/users/me/stats').set(auth(session)).expect(200);
    expect(stats.body).toMatchObject({ runsRecorded: 0, best: null, rank: null, totalPlayers: 0 });

    await request(app).get('/v1/leaderboard?limit=0').expect(422);
    await request(app).get('/v1/leaderboard?offset=-1').expect(422);
    await request(app).get('/v1/users/search?q=&limit=51').expect(422);
    await request(app).get('/v1/scores/me?before=not-a-date').set(auth(session)).expect(422);
    await request(app).get('/v1/scores/not-a-uuid').set(auth(session)).expect(422);
  });

  it('paginates and validates dated challenge leaderboards', async () => {
    const rival = await registerUser(app, 'contract_rival');
    await request(app)
      .post('/v1/challenges/today/entries')
      .set(auth(session))
      .send({ score: 11 })
      .expect(201);
    await request(app)
      .post('/v1/challenges/today/entries')
      .set(auth(rival))
      .send({ score: 22 })
      .expect(201);

    const date = new Date().toISOString().slice(0, 10);
    const first = await request(app)
      .get(`/v1/challenges/${date}/leaderboard?limit=1&offset=0`)
      .expect(200);
    expect(first.body).toMatchObject({ total: 2, limit: 1, offset: 0, hasMore: true });
    expect(first.body.items[0]).toMatchObject({ username: 'contract_rival', rank: 1 });

    const second = await request(app)
      .get(`/v1/challenges/${date}/leaderboard?limit=1&offset=1`)
      .expect(200);
    expect(second.body).toMatchObject({ total: 2, limit: 1, offset: 1, hasMore: false });
    expect(second.body.items[0]).toMatchObject({ username: session.username, rank: 2 });

    await request(app).get(`/v1/challenges/${date}/leaderboard?limit=0`).expect(422);
  });
});
