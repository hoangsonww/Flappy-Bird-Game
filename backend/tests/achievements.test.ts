import { beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { auth, freshApp, registerUser, submitRun, type TestSession } from './helpers.js';

describe('achievements', () => {
  let app: Express;
  let session: TestSession;

  beforeEach(async () => {
    app = await freshApp();
    session = await registerUser(app, 'collector');
  });

  it('publishes the catalog without authentication', async () => {
    const response = await request(app).get('/v1/achievements').expect(200);
    expect(response.body.total).toBeGreaterThan(10);
    expect(response.body.totalPoints).toBeGreaterThan(0);
    expect(response.body.items[0]).toHaveProperty('metric');
  });

  it('annotates the catalog with the caller’s progress', async () => {
    await submitRun(app, session, 12);
    const response = await request(app).get('/v1/achievements/me').set(auth(session)).expect(200);

    const first = response.body.items.find(
      (item: { code: string }) => item.code === 'first_flight',
    );
    expect(first.unlocked).toBe(true);
    expect(response.body.unlocked).toBeGreaterThanOrEqual(2);
    expect(response.body.points).toBeGreaterThan(0);
  });

  it('merges client-side unlocks and keeps the merge monotonic', async () => {
    const unlockedAt = '2026-03-19T02:11:00.000Z';

    await request(app)
      .post('/v1/achievements/me/sync')
      .set(auth(session))
      .send({ achievements: [{ code: 'night_owl', progress: 1, unlockedAt }] })
      .expect(200);

    // A later sync with lower progress and no timestamp must not regress state.
    const second = await request(app)
      .post('/v1/achievements/me/sync')
      .set(auth(session))
      .send({ achievements: [{ code: 'night_owl', progress: 0 }] })
      .expect(200);

    expect(second.body.items[0].progress).toBe(1);
    expect(second.body.items[0].unlockedAt).toBe(unlockedAt);
  });

  it('rejects unknown achievement codes', async () => {
    const response = await request(app)
      .post('/v1/achievements/me/sync')
      .set(auth(session))
      .send({ achievements: [{ code: 'not_a_real_achievement', progress: 1 }] })
      .expect(400);
    expect(response.body.error.details.codes).toContain('not_a_real_achievement');
  });

  it('requires authentication to sync', async () => {
    await request(app)
      .post('/v1/achievements/me/sync')
      .send({ achievements: [{ code: 'night_owl' }] })
      .expect(401);
  });
});
