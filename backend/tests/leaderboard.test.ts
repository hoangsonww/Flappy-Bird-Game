import { beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { auth, freshApp, registerUser, submitRun, type TestSession } from './helpers.js';

describe('leaderboards', () => {
  let app: Express;
  let alice: TestSession;
  let bob: TestSession;
  let carol: TestSession;

  beforeEach(async () => {
    app = await freshApp();
    alice = await registerUser(app, 'alice');
    bob = await registerUser(app, 'bob');
    carol = await registerUser(app, 'carol');

    await submitRun(app, alice, 50);
    await submitRun(app, bob, 30);
    await submitRun(app, carol, 70);
  });

  it('ranks players by their best run, highest first', async () => {
    const response = await request(app).get('/v1/leaderboard').expect(200);
    expect(response.body.items.map((entry: { username: string }) => entry.username)).toEqual([
      'carol',
      'alice',
      'bob',
    ]);
    expect(response.body.items[0].rank).toBe(1);
    expect(response.body.total).toBe(3);
  });

  it('shows each player only once, using their best run', async () => {
    await submitRun(app, bob, 90);
    const response = await request(app).get('/v1/leaderboard').expect(200);

    expect(response.body.total).toBe(3);
    expect(response.body.items[0].username).toBe('bob');
    expect(response.body.items[0].score).toBe(90);
  });

  it('paginates with limit and offset', async () => {
    const first = await request(app).get('/v1/leaderboard?limit=2&offset=0').expect(200);
    expect(first.body.items).toHaveLength(2);
    expect(first.body.hasMore).toBe(true);

    const second = await request(app).get('/v1/leaderboard?limit=2&offset=2').expect(200);
    expect(second.body.items).toHaveLength(1);
    expect(second.body.hasMore).toBe(false);
  });

  it('filters by game mode', async () => {
    await submitRun(app, alice, 15, { mode: 'hardcore' });
    const response = await request(app).get('/v1/leaderboard?mode=hardcore').expect(200);

    expect(response.body.total).toBe(1);
    expect(response.body.items[0].username).toBe('alice');
    expect(response.body.items[0].score).toBe(15);
  });

  it('gives tied players the same rank', async () => {
    const dave = await registerUser(app, 'dave');
    await submitRun(app, dave, 70);

    const response = await request(app).get('/v1/leaderboard').expect(200);
    const top = response.body.items.filter((entry: { score: number }) => entry.score === 70);
    expect(top).toHaveLength(2);
    expect(top[0].rank).toBe(top[1].rank);
  });

  it('supports every time window', async () => {
    for (const window of ['all', 'daily', 'weekly', 'monthly']) {
      const response = await request(app).get(`/v1/leaderboard?window=${window}`).expect(200);
      expect(response.body.window).toBe(window);
      expect(response.body.total).toBe(3);
    }
  });

  it('rejects an unknown window', async () => {
    await request(app).get('/v1/leaderboard?window=yearly').expect(422);
  });

  it('reports own rank with neighbours', async () => {
    const response = await request(app)
      .get('/v1/leaderboard/me?radius=1')
      .set(auth(alice))
      .expect(200);

    expect(response.body.rank).toBe(2);
    expect(response.body.total).toBe(3);
    expect(response.body.entry.username).toBe('alice');
    expect(response.body.neighbours.length).toBeGreaterThanOrEqual(2);
  });

  it('returns a null rank for a player with no runs', async () => {
    const rookie = await registerUser(app, 'rookie');
    const response = await request(app).get('/v1/leaderboard/me').set(auth(rookie)).expect(200);
    expect(response.body.rank).toBeNull();
    expect(response.body.neighbours).toEqual([]);
  });

  it('builds a friends board from the follow graph', async () => {
    await request(app).put('/v1/friends/bob').set(auth(alice)).expect(201);

    const response = await request(app).get('/v1/leaderboard/friends').set(auth(alice)).expect(200);
    const names = response.body.items.map((entry: { username: string }) => entry.username);

    expect(names).toContain('alice');
    expect(names).toContain('bob');
    expect(names).not.toContain('carol');
    expect(response.body.items[0].rank).toBe(1);
  });

  it('hides banned players from the board', async () => {
    await request(app)
      .post('/v1/admin/users/carol/ban')
      .set('X-Admin-Token', 'test-admin-token')
      .send({ reason: 'testing' })
      .expect(200);

    const response = await request(app).get('/v1/leaderboard').expect(200);
    const names = response.body.items.map((entry: { username: string }) => entry.username);
    expect(names).not.toContain('carol');
    expect(response.body.total).toBe(2);
  });
});
