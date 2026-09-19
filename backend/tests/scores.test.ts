import { beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import {
  auth,
  freshApp,
  registerUser,
  runPayload,
  submitRun,
  type TestSession,
} from './helpers.js';

describe('score submission', () => {
  let app: Express;
  let session: TestSession;

  beforeEach(async () => {
    app = await freshApp();
    session = await registerUser(app, 'runner');
  });

  it('stores a clean run and returns rank plus stats', async () => {
    const response = await submitRun(app, session, 42);

    expect(response.body.score.score).toBe(42);
    expect(response.body.flagged).toBe(false);
    expect(response.body.personalBest).toBe(true);
    expect(response.body.rank).toBe(1);
    expect(response.body.stats.gamesPlayed).toBe(1);
    expect(response.body.stats.bestScore).toBe(42);
  });

  it('accumulates aggregate stats across runs', async () => {
    await submitRun(app, session, 10);
    const second = await submitRun(app, session, 25);

    expect(second.body.stats.gamesPlayed).toBe(2);
    expect(second.body.stats.bestScore).toBe(25);
    expect(second.body.stats.totalScore).toBe(35);
  });

  it('does not report a personal best when the score is lower', async () => {
    await submitRun(app, session, 30);
    const second = await submitRun(app, session, 12);
    expect(second.body.personalBest).toBe(false);
    expect(second.body.stats.bestScore).toBe(30);
  });

  it('unlocks stat-driven achievements as thresholds are crossed', async () => {
    const response = await submitRun(app, session, 27);
    const codes = response.body.unlockedAchievements.map((entry: { code: string }) => entry.code);
    expect(codes).toContain('first_flight');
    expect(codes).toContain('getting_warm');
    expect(codes).toContain('sky_rookie');
  });

  it('does not re-report an achievement that is already unlocked', async () => {
    await submitRun(app, session, 27);
    const second = await submitRun(app, session, 28);
    expect(second.body.unlockedAchievements).toHaveLength(0);
  });

  it('rejects a score higher than the pipes passed', async () => {
    const response = await request(app)
      .post('/v1/scores')
      .set(auth(session))
      .send({ ...runPayload(20), pipesPassed: 5 })
      .expect(422);
    expect(response.body.error.code).toBe('unprocessable');
  });

  it('rejects a scoring run with zero duration', async () => {
    await request(app)
      .post('/v1/scores')
      .set(auth(session))
      .send({ ...runPayload(5), durationMs: 0 })
      .expect(422);
  });

  it('flags an implausibly fast run and keeps it off the board', async () => {
    const response = await request(app)
      .post('/v1/scores')
      .set(auth(session))
      .send({ ...runPayload(80), durationMs: 1_000 })
      .expect(201);

    expect(response.body.flagged).toBe(true);
    expect(response.body.flagReasons.join(' ')).toMatch(/too short/);
    expect(response.body.rank).toBeNull();

    const board = await request(app).get('/v1/leaderboard').expect(200);
    expect(board.body.total).toBe(0);
  });

  it('flags a run with disproportionate coins', async () => {
    const response = await request(app)
      .post('/v1/scores')
      .set(auth(session))
      .send({ ...runPayload(10), coins: 500 })
      .expect(201);
    expect(response.body.flagged).toBe(true);
  });

  it('never lets a flagged run affect aggregate stats', async () => {
    await submitRun(app, session, 20);
    await request(app)
      .post('/v1/scores')
      .set(auth(session))
      .send({ ...runPayload(500), durationMs: 900 })
      .expect(201);

    const stats = await request(app).get('/v1/users/me/stats').set(auth(session)).expect(200);
    expect(stats.body.stats.bestScore).toBe(20);
    expect(stats.body.stats.gamesPlayed).toBe(1);
  });

  it('returns run history newest first with a paging cursor', async () => {
    await submitRun(app, session, 5);
    await submitRun(app, session, 7);
    await submitRun(app, session, 9);

    const response = await request(app).get('/v1/scores/me?limit=2').set(auth(session)).expect(200);

    expect(response.body.items).toHaveLength(2);
    expect(response.body.items[0].score).toBe(9);
    expect(response.body.nextBefore).toBeTruthy();
  });

  it('filters run history by mode', async () => {
    await submitRun(app, session, 5, { mode: 'classic' });
    await submitRun(app, session, 8, { mode: 'hardcore' });

    const response = await request(app)
      .get('/v1/scores/me?mode=hardcore')
      .set(auth(session))
      .expect(200);

    expect(response.body.items).toHaveLength(1);
    expect(response.body.items[0].mode).toBe('hardcore');
  });

  it('exposes the personal best per mode', async () => {
    await submitRun(app, session, 11, { mode: 'classic' });
    await submitRun(app, session, 33, { mode: 'endless' });

    const classic = await request(app).get('/v1/scores/me/best?mode=classic').set(auth(session));
    const overall = await request(app).get('/v1/scores/me/best').set(auth(session));

    expect(classic.body.best.score).toBe(11);
    expect(overall.body.best.score).toBe(33);
  });

  it('refuses to reveal another player’s run', async () => {
    const mine = await submitRun(app, session, 15);
    const other = await registerUser(app, 'nosy');

    await request(app).get(`/v1/scores/${mine.body.score.id}`).set(auth(other)).expect(403);
    await request(app).get(`/v1/scores/${mine.body.score.id}`).set(auth(session)).expect(200);
  });

  it('requires authentication to submit', async () => {
    await request(app).post('/v1/scores').send(runPayload(10)).expect(401);
  });
});
