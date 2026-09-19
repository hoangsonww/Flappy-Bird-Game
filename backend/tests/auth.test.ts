import { beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { auth, freshApp, registerUser } from './helpers.js';

describe('authentication', () => {
  let app: Express;

  beforeEach(async () => {
    app = await freshApp();
  });

  it('registers an account and returns a usable token pair', async () => {
    const response = await request(app)
      .post('/v1/auth/register')
      .send({ username: 'skyhopper', password: 'flappybird123', country: 'vn' })
      .expect(201);

    expect(response.body.user.username).toBe('skyhopper');
    expect(response.body.user.country).toBe('VN');
    expect(response.body.tokens.tokenType).toBe('Bearer');
    expect(response.body.tokens.expiresIn).toBeGreaterThan(0);
    expect(response.body.user).not.toHaveProperty('passwordHash');
  });

  it('rejects a duplicate username case-insensitively', async () => {
    await registerUser(app, 'skyhopper');
    const response = await request(app)
      .post('/v1/auth/register')
      .send({ username: 'SkyHopper', password: 'flappybird123' })
      .expect(409);
    expect(response.body.error.code).toBe('conflict');
  });

  it('rejects weak passwords with field-level detail', async () => {
    const response = await request(app)
      .post('/v1/auth/register')
      .send({ username: 'shorty', password: 'abc' })
      .expect(422);
    expect(response.body.error.code).toBe('validation_failed');
    expect(response.body.error.details.issues[0].path).toBe('password');
  });

  it('rejects malformed usernames', async () => {
    await request(app)
      .post('/v1/auth/register')
      .send({ username: 'no spaces', password: 'flappybird123' })
      .expect(422);
  });

  it('logs in with valid credentials and rejects invalid ones', async () => {
    await registerUser(app, 'skyhopper');

    await request(app)
      .post('/v1/auth/login')
      .send({ username: 'skyhopper', password: 'flappybird123' })
      .expect(200);

    const failure = await request(app)
      .post('/v1/auth/login')
      .send({ username: 'skyhopper', password: 'wrong-password' })
      .expect(401);
    expect(failure.body.error.code).toBe('invalid_credentials');
  });

  it('creates a guest on first call and resumes it on the second', async () => {
    const deviceId = 'DEVICE-1234567890';

    const created = await request(app).post('/v1/auth/guest').send({ deviceId }).expect(201);
    expect(created.body.user.isGuest).toBe(true);

    const resumed = await request(app).post('/v1/auth/guest').send({ deviceId }).expect(200);
    expect(resumed.body.user.id).toBe(created.body.user.id);
  });

  it('upgrades a guest while keeping its identity', async () => {
    const guest = await request(app)
      .post('/v1/auth/guest')
      .send({ deviceId: 'DEVICE-UPGRADE-01' })
      .expect(201);

    const upgraded = await request(app)
      .post('/v1/auth/upgrade')
      .set({ Authorization: `Bearer ${guest.body.tokens.accessToken}` })
      .send({ username: 'promoted', password: 'flappybird123' })
      .expect(200);

    expect(upgraded.body.user.id).toBe(guest.body.user.id);
    expect(upgraded.body.user.username).toBe('promoted');
    expect(upgraded.body.user.isGuest).toBe(false);
  });

  it('rotates refresh tokens and refuses to reuse the consumed one', async () => {
    const session = await registerUser(app, 'rotator');

    const first = await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: session.refreshToken })
      .expect(200);

    expect(first.body.tokens.refreshToken).not.toBe(session.refreshToken);

    const replay = await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: session.refreshToken })
      .expect(401);
    expect(replay.body.error.code).toBe('unauthorized');
  });

  it('revokes a refresh token on logout', async () => {
    const session = await registerUser(app, 'byebye');
    await request(app)
      .post('/v1/auth/logout')
      .send({ refreshToken: session.refreshToken })
      .expect(204);
    await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: session.refreshToken })
      .expect(401);
  });

  it('requires a bearer token for protected routes', async () => {
    const response = await request(app).get('/v1/auth/me').expect(401);
    expect(response.body.error.code).toBe('unauthorized');
  });

  it('rejects a garbage bearer token', async () => {
    await request(app).get('/v1/auth/me').set({ Authorization: 'Bearer not-a-jwt' }).expect(401);
  });

  it('changes a password and invalidates existing sessions', async () => {
    const session = await registerUser(app, 'changer');

    await request(app)
      .patch('/v1/auth/password')
      .set(auth(session))
      .send({ currentPassword: 'flappybird123', newPassword: 'evenbetterpassword' })
      .expect(204);

    await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: session.refreshToken })
      .expect(401);
    await request(app)
      .post('/v1/auth/login')
      .send({ username: 'changer', password: 'evenbetterpassword' })
      .expect(200);
  });

  it('refuses a password change with the wrong current password', async () => {
    const session = await registerUser(app, 'nope');
    await request(app)
      .patch('/v1/auth/password')
      .set(auth(session))
      .send({ currentPassword: 'incorrect', newPassword: 'anotherpassword' })
      .expect(401);
  });

  it('deletes the account and its sessions', async () => {
    const session = await registerUser(app, 'goodbye');
    await request(app).delete('/v1/auth/account').set(auth(session)).expect(204);
    await request(app).get('/v1/auth/me').set(auth(session)).expect(401);
  });
});
