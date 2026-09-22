import { beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { deriveDailyChallenge } from '../src/domain/challenge.js';
import { auth, freshApp, registerUser, type TestSession } from './helpers.js';

const today = () => new Date().toISOString().slice(0, 10);

describe('daily challenges', () => {
  let app: Express;
  let session: TestSession;

  beforeEach(async () => {
    app = await freshApp();
    session = await registerUser(app, 'challenger');
  });

  it('derives the same challenge on the client and the server', async () => {
    const response = await request(app).get('/v1/challenges/today').expect(200);
    const expected = deriveDailyChallenge(today());

    expect(response.body.challenge.seed).toBe(expected.seed);
    expect(response.body.challenge.mode).toBe(expected.mode);
    expect(response.body.challenge.pipeGap).toBe(expected.pipeGap);
    expect(response.body.rollsOverAt.endsWith('T00:00:00.000Z')).toBe(true);
  });

  it('is deterministic and date-dependent', () => {
    // `createdAt` is wall-clock metadata, not part of the derived parameters.
    const parameters = ({
      createdAt: _createdAt,
      ...rest
    }: ReturnType<typeof deriveDailyChallenge>) => rest;

    expect(parameters(deriveDailyChallenge('2026-03-19'))).toEqual(
      parameters(deriveDailyChallenge('2026-03-19')),
    );
    expect(deriveDailyChallenge('2026-03-19').seed).not.toBe(
      deriveDailyChallenge('2026-03-20').seed,
    );
  });

  it('serves a challenge for an arbitrary date', async () => {
    const response = await request(app).get('/v1/challenges/2026-01-01').expect(200);
    expect(response.body.challenge.date).toBe('2026-01-01');
  });

  it('rejects a malformed date', async () => {
    await request(app).get('/v1/challenges/19-03-2026').expect(422);
  });

  it('keeps only the best entry per player per day', async () => {
    await request(app)
      .post('/v1/challenges/today/entries')
      .set(auth(session))
      .send({ score: 30 })
      .expect(201);

    const lower = await request(app)
      .post('/v1/challenges/today/entries')
      .set(auth(session))
      .send({ score: 10 })
      .expect(201);
    expect(lower.body.entry.score).toBe(30);

    const higher = await request(app)
      .post('/v1/challenges/today/entries')
      .set(auth(session))
      .send({ score: 55 })
      .expect(201);
    expect(higher.body.entry.score).toBe(55);
  });

  it('ranks the challenge board', async () => {
    const rival = await registerUser(app, 'rival');
    await request(app).post('/v1/challenges/today/entries').set(auth(session)).send({ score: 20 });
    await request(app).post('/v1/challenges/today/entries').set(auth(rival)).send({ score: 45 });

    const response = await request(app).get(`/v1/challenges/${today()}/leaderboard`).expect(200);
    expect(response.body.items[0].username).toBe('rival');
    expect(response.body.items[0].rank).toBe(1);
    expect(response.body.total).toBe(2);
  });

  it('refuses entries for a past date', async () => {
    await request(app)
      .post('/v1/challenges/2026-01-01/entries')
      .set(auth(session))
      .send({ score: 10 })
      .expect(400);
  });

  it('records a daily-mode run on the challenge board automatically', async () => {
    await request(app)
      .post('/v1/scores')
      .set(auth(session))
      .send({
        score: 18,
        mode: 'daily',
        pipesPassed: 18,
        durationMs: 30_000,
        coins: 4,
        seed: 'daily-seed',
      })
      .expect(201);

    const board = await request(app).get(`/v1/challenges/${today()}/leaderboard`).expect(200);
    expect(board.body.items.some((entry: { score: number }) => entry.score === 18)).toBe(true);
  });
});
