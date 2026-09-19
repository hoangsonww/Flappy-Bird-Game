import { beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { auth, freshApp, registerUser, submitRun, type TestSession } from './helpers.js';

describe('profiles and friends', () => {
  let app: Express;
  let session: TestSession;

  beforeEach(async () => {
    app = await freshApp();
    session = await registerUser(app, 'profiler', { displayName: 'The Profiler', country: 'DE' });
  });

  it('returns a public profile with stats, rank and achievement summary', async () => {
    await submitRun(app, session, 33);
    const response = await request(app).get('/v1/users/profiler').expect(200);

    expect(response.body.user.displayName).toBe('The Profiler');
    expect(response.body.user).not.toHaveProperty('email');
    expect(response.body.stats.bestScore).toBe(33);
    expect(response.body.best.score).toBe(33);
    expect(response.body.rank).toBe(1);
    expect(response.body.achievements.total).toBeGreaterThan(0);
  });

  it('404s for an unknown player', async () => {
    await request(app).get('/v1/users/ghost_user').expect(404);
  });

  it('updates the profile and validates the skin', async () => {
    const ok = await request(app)
      .patch('/v1/users/me')
      .set(auth(session))
      .send({ displayName: 'Renamed', avatarSkin: 'aurora', country: 'jp' })
      .expect(200);

    expect(ok.body.user.displayName).toBe('Renamed');
    expect(ok.body.user.avatarSkin).toBe('aurora');
    expect(ok.body.user.country).toBe('JP');

    await request(app)
      .patch('/v1/users/me')
      .set(auth(session))
      .send({ avatarSkin: 'invisible-bird' })
      .expect(422);
  });

  it('rejects an empty profile patch', async () => {
    await request(app).patch('/v1/users/me').set(auth(session)).send({}).expect(422);
  });

  it('searches players by username and display name', async () => {
    await registerUser(app, 'searchme', { displayName: 'Findable Bird' });

    const byUsername = await request(app).get('/v1/users/search?q=searchm').expect(200);
    expect(byUsername.body.items).toHaveLength(1);

    const byDisplayName = await request(app).get('/v1/users/search?q=findable').expect(200);
    expect(byDisplayName.body.items[0].username).toBe('searchme');
  });

  it('lists a player’s recent runs and hides flagged ones', async () => {
    await submitRun(app, session, 12);
    await request(app)
      .post('/v1/scores')
      .set(auth(session))
      .send({ score: 400, mode: 'classic', pipesPassed: 400, durationMs: 1_000 })
      .expect(201);

    const response = await request(app).get('/v1/users/profiler/scores').expect(200);
    expect(response.body.items).toHaveLength(1);
    expect(response.body.items[0].score).toBe(12);
  });

  it('follows and unfollows another player', async () => {
    await registerUser(app, 'followed');

    await request(app).put('/v1/friends/followed').set(auth(session)).expect(201);
    let list = await request(app).get('/v1/friends').set(auth(session)).expect(200);
    expect(list.body.total).toBe(1);
    expect(list.body.items[0].username).toBe('followed');

    // Following twice is idempotent.
    await request(app).put('/v1/friends/followed').set(auth(session)).expect(201);
    list = await request(app).get('/v1/friends').set(auth(session)).expect(200);
    expect(list.body.total).toBe(1);

    await request(app).delete('/v1/friends/followed').set(auth(session)).expect(204);
    list = await request(app).get('/v1/friends').set(auth(session)).expect(200);
    expect(list.body.total).toBe(0);
  });

  it('refuses self-follow and unknown targets', async () => {
    await request(app).put('/v1/friends/profiler').set(auth(session)).expect(400);
    await request(app).put('/v1/friends/nobody_here').set(auth(session)).expect(404);
  });
});
