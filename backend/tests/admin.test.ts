import { beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { auth, freshApp, registerUser, submitRun, type TestSession } from './helpers.js';

const adminHeader = { 'X-Admin-Token': 'test-admin-token' };

describe('moderation', () => {
  let app: Express;
  let player: TestSession;

  beforeEach(async () => {
    app = await freshApp();
    player = await registerUser(app, 'suspect');
  });

  it('refuses access without an admin credential', async () => {
    await request(app).get('/v1/admin/stats').expect(403);
    await request(app).get('/v1/admin/stats').set(auth(player)).expect(403);
  });

  it('accepts the static admin token', async () => {
    const response = await request(app).get('/v1/admin/stats').set(adminHeader).expect(200);
    expect(response.body.users).toBe(1);
    expect(['memory', 'postgres']).toContain(response.body.driver);
  });

  it('bans and unbans a player', async () => {
    await submitRun(app, player, 25);

    await request(app)
      .post('/v1/admin/users/suspect/ban')
      .set(adminHeader)
      .send({ reason: 'macro use' })
      .expect(200);

    // Banned players lose their sessions and disappear from public surfaces.
    await request(app).get('/v1/auth/me').set(auth(player)).expect(403);
    await request(app).get('/v1/users/suspect').expect(404);
    await request(app)
      .post('/v1/auth/login')
      .send({ username: 'suspect', password: 'flappybird123' })
      .expect(403);

    await request(app).delete('/v1/admin/users/suspect/ban').set(adminHeader).expect(200);
    await request(app).get('/v1/users/suspect').expect(200);
  });

  it('flags a run and recomputes the owner’s stats', async () => {
    const high = await submitRun(app, player, 90);
    await submitRun(app, player, 20);

    await request(app)
      .post(`/v1/admin/scores/${high.body.score.id}/flag`)
      .set(adminHeader)
      .send({ reason: 'impossible trajectory' })
      .expect(200);

    const stats = await request(app).get('/v1/users/me/stats').set(auth(player)).expect(200);
    expect(stats.body.stats.bestScore).toBe(20);

    const board = await request(app).get('/v1/leaderboard').expect(200);
    expect(board.body.items[0].score).toBe(20);
  });

  it('deletes a run', async () => {
    const run = await submitRun(app, player, 40);
    await request(app).delete(`/v1/admin/scores/${run.body.score.id}`).set(adminHeader).expect(204);
    await request(app).delete(`/v1/admin/scores/${run.body.score.id}`).set(adminHeader).expect(404);
  });

  it('purges expired tokens and recomputes stats on demand', async () => {
    const purge = await request(app)
      .post('/v1/admin/maintenance/purge-tokens')
      .set(adminHeader)
      .expect(200);
    expect(purge.body.purged).toBe(0);

    await submitRun(app, player, 17);
    const recompute = await request(app)
      .post('/v1/admin/maintenance/recompute-stats/suspect')
      .set(adminHeader)
      .expect(200);
    expect(recompute.body.stats.bestScore).toBe(17);
  });
});
