import { beforeEach, describe, expect, it } from 'vitest';
import { deriveDailyChallenge } from '../src/domain/challenge.js';
import type { NewScore } from '../src/domain/models.js';
import { getRepositories } from '../src/repositories/index.js';
import { freshApp } from './helpers.js';

const createPlayer = async (username: string, suffix = username) =>
  getRepositories().users.create({
    username,
    email: `${suffix}@example.com`,
    passwordHash: `hash-${suffix}`,
    displayName: `Player ${suffix}`,
    country: 'US',
    avatarSkin: 'classic',
    isGuest: false,
    deviceId: `device-${suffix}`,
  });

const run = (userId: string, score: number, patch: Partial<NewScore> = {}): NewScore => ({
  userId,
  score,
  mode: 'classic',
  coins: Math.min(score, 5),
  pipesPassed: score,
  durationMs: score * 1_000 + 2_000,
  maxCombo: Math.min(score, 5),
  powerUpsUsed: 0,
  seed: `seed-${score}`,
  clientVersion: '1.0.0-test',
  deviceModel: 'test-device',
  ...patch,
});

/**
 * Driver parity suite. Every case runs unchanged with DB_DRIVER=memory and
 * DB_DRIVER=postgres, preventing either repository implementation from
 * drifting away from the shared contract.
 */
describe('repository contract', () => {
  beforeEach(async () => {
    await freshApp();
  });

  it('creates, locates, searches, updates and removes users', async () => {
    const repos = getRepositories();
    const first = await createPlayer('repo_alpha', 'alpha');
    const second = await createPlayer('repo_beta', 'beta');

    expect(await repos.users.count()).toBe(2);
    expect((await repos.users.findById(first.id))?.username).toBe('repo_alpha');
    expect((await repos.users.findByUsername('REPO_ALPHA'))?.id).toBe(first.id);
    expect((await repos.users.findByEmail('ALPHA@example.com'))?.id).toBe(first.id);
    expect((await repos.users.findByDeviceId('device-alpha'))?.id).toBe(first.id);
    const missingId = '00000000-0000-4000-8000-000000000001';
    const foundIds = (await repos.users.findManyByIds([second.id, missingId, first.id])).map(
      (user) => user.id,
    );
    expect(foundIds).toHaveLength(2);
    expect(new Set(foundIds)).toEqual(new Set([second.id, first.id]));
    expect((await repos.users.search('player alpha', 5)).map((u) => u.id)).toEqual([first.id]);

    const beforeTouch = first.lastSeenAt;
    await repos.users.touchLastSeen(first.id);
    expect(Date.parse((await repos.users.findById(first.id))!.lastSeenAt)).toBeGreaterThanOrEqual(
      Date.parse(beforeTouch),
    );
    const updated = await repos.users.update(first.id, {
      displayName: 'Updated Bird',
      country: null,
      avatarSkin: 'aurora',
    });
    expect(updated).toMatchObject({
      displayName: 'Updated Bird',
      country: null,
      avatarSkin: 'aurora',
    });

    await repos.users.remove(second.id);
    expect(await repos.users.findById(second.id)).toBeNull();
    expect(await repos.users.count()).toBe(1);
  });

  it('enforces unique user identities and missing-record behavior', async () => {
    const repos = getRepositories();
    const first = await createPlayer('unique_bird', 'unique');
    await expect(createPlayer('UNIQUE_BIRD', 'other')).rejects.toMatchObject({ code: 'conflict' });
    await expect(
      repos.users.create({
        username: 'email_bird',
        email: 'UNIQUE@example.com',
        passwordHash: 'hash',
        displayName: 'Email Bird',
        country: null,
        avatarSkin: 'classic',
        isGuest: false,
        deviceId: 'device-email',
      }),
    ).rejects.toMatchObject({ code: 'conflict' });
    await expect(
      repos.users.update('00000000-0000-4000-8000-000000000000', {}),
    ).rejects.toMatchObject({ code: 'not_found' });
    await expect(repos.users.update(first.id, { username: 'unique_bird' })).resolves.toMatchObject({
      id: first.id,
    });
  });

  it('issues, revokes, counts and purges refresh tokens', async () => {
    const repos = getRepositories();
    const user = await createPlayer('token_bird');
    const active = await repos.tokens.issue({
      userId: user.id,
      tokenHash: 'active-hash',
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      userAgent: 'repository-test',
    });
    await repos.tokens.issue({
      userId: user.id,
      tokenHash: 'expired-hash',
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
      userAgent: null,
    });

    expect((await repos.tokens.findByHash('active-hash'))?.id).toBe(active.id);
    expect(await repos.tokens.countActiveForUser(user.id)).toBe(1);
    expect(await repos.tokens.purgeExpired()).toBe(1);
    await repos.tokens.revoke(active.id);
    expect(await repos.tokens.countActiveForUser(user.id)).toBe(0);
    expect(await repos.tokens.revokeAllForUser(user.id)).toBe(0);
  });

  it('stores, filters, ranks, flags and removes scores', async () => {
    const repos = getRepositories();
    const alpha = await createPlayer('score_alpha', 'score-alpha');
    const beta = await createPlayer('score_beta', 'score-beta');
    const low = await repos.scores.insert(run(alpha.id, 10));
    const high = await repos.scores.insert(run(alpha.id, 30, { mode: 'hardcore' }));
    await repos.scores.insert(run(beta.id, 20));

    expect((await repos.scores.findById(low.id))?.score).toBe(10);
    expect(await repos.scores.countForUser(alpha.id)).toBe(2);
    expect((await repos.scores.bestForUser(alpha.id, null))?.id).toBe(high.id);
    expect((await repos.scores.bestForUser(alpha.id, 'classic'))?.id).toBe(low.id);
    expect(
      await repos.scores.listByUser({ userId: alpha.id, limit: 5, mode: 'hardcore', before: null }),
    ).toHaveLength(1);
    expect(await repos.scores.countForUserSince(alpha.id, '2000-01-01T00:00:00.000Z')).toBe(2);

    const board = await repos.scores.leaderboard({
      mode: null,
      window: 'all',
      limit: 10,
      offset: 0,
    });
    expect(board.entries.map((entry) => entry.score)).toEqual([30, 20]);
    expect(
      (await repos.scores.rankForUser(beta.id, { mode: null, window: 'all' }))?.entry.rank,
    ).toBe(2);
    expect(
      await repos.scores.neighboursForRank({
        mode: null,
        window: 'all',
        limit: 3,
        offset: 0,
        rank: 2,
        radius: 1,
      }),
    ).toHaveLength(2);

    await repos.scores.flag(high.id, 'repository test');
    expect((await repos.scores.findById(high.id))?.flagged).toBe(true);
    expect((await repos.scores.bestForUser(alpha.id, null))?.id).toBe(low.id);
    await repos.scores.remove(low.id);
    expect(await repos.scores.findById(low.id)).toBeNull();
  });

  it('aggregates and recomputes player statistics', async () => {
    const repos = getRepositories();
    const alpha = await createPlayer('stats_alpha', 'stats-alpha');
    const beta = await createPlayer('stats_beta', 'stats-beta');
    const first = await repos.scores.insert(run(alpha.id, 8, { coins: 3, maxCombo: 3 }));
    const second = await repos.scores.insert(run(alpha.id, 18, { coins: 7, maxCombo: 6 }));
    const rival = await repos.scores.insert(run(beta.id, 12, { coins: 2 }));
    await repos.stats.applyScore(first);
    await repos.stats.applyScore(second);
    await repos.stats.applyScore(rival);

    expect(await repos.stats.get(alpha.id)).toMatchObject({
      bestScore: 18,
      totalScore: 26,
      gamesPlayed: 2,
      totalCoins: 10,
      bestCombo: 6,
    });
    expect((await repos.stats.topByMetric('bestScore', 1))[0]?.userId).toBe(alpha.id);
    expect(await repos.stats.globalTotals()).toMatchObject({ players: 2, games: 3, coins: 12 });

    await repos.scores.flag(second.id, 'exclude from stats');
    expect(await repos.stats.recompute(alpha.id)).toMatchObject({ bestScore: 8, gamesPlayed: 1 });
  });

  it('persists achievement progress monotonically', async () => {
    const repos = getRepositories();
    const user = await createPlayer('achievement_bird');
    const catalog = await repos.achievements.catalog();
    expect(catalog.length).toBeGreaterThan(0);
    expect(await repos.achievements.findDefinition(catalog[0]!.code)).toEqual(catalog[0]);
    expect(await repos.achievements.findDefinition('missing-code')).toBeNull();

    await repos.achievements.upsert({
      userId: user.id,
      code: catalog[0]!.code,
      progress: 8,
      unlockedAt: null,
    });
    await repos.achievements.upsertMany([
      { userId: user.id, code: catalog[0]!.code, progress: 3, unlockedAt: null },
      {
        userId: user.id,
        code: catalog[1]!.code,
        progress: 10,
        unlockedAt: '2026-01-01T00:00:00.000Z',
      },
    ]);
    const progress = await repos.achievements.forUser(user.id);
    expect(progress).toHaveLength(2);
    expect(progress.find((entry) => entry.code === catalog[0]!.code)?.progress).toBe(8);
  });

  it('manages friendships and limits friend leaderboards to the supplied graph', async () => {
    const repos = getRepositories();
    const owner = await createPlayer('friend_owner', 'friend-owner');
    const friend = await createPlayer('friend_target', 'friend-target');
    const outsider = await createPlayer('friend_outside', 'friend-outside');
    await repos.scores.insert(run(owner.id, 10));
    await repos.scores.insert(run(friend.id, 30));
    await repos.scores.insert(run(outsider.id, 50));

    await repos.friends.add(owner.id, friend.id);
    expect(await repos.friends.exists(owner.id, friend.id)).toBe(true);
    expect(await repos.friends.list(owner.id)).toHaveLength(1);
    const board = await repos.scores.leaderboardForUserIds([owner.id, friend.id], {
      mode: null,
      window: 'all',
      limit: 10,
    });
    expect(board.map((entry) => entry.userId)).toEqual([friend.id, owner.id]);

    await repos.friends.remove(owner.id, friend.id);
    expect(await repos.friends.exists(owner.id, friend.id)).toBe(false);
  });

  it('materializes challenges and keeps each player best entry', async () => {
    const repos = getRepositories();
    const alpha = await createPlayer('challenge_alpha', 'challenge-alpha');
    const beta = await createPlayer('challenge_beta', 'challenge-beta');
    const challenge = deriveDailyChallenge('2026-06-01');
    expect(await repos.challenges.getByDate(challenge.date)).toBeNull();
    await repos.challenges.create(challenge);
    expect((await repos.challenges.getByDate(challenge.date))?.seed).toBe(challenge.seed);

    await repos.challenges.upsertEntry({
      date: challenge.date,
      userId: alpha.id,
      score: 20,
      submittedAt: '2026-06-01T01:00:00.000Z',
    });
    await repos.challenges.upsertEntry({
      date: challenge.date,
      userId: alpha.id,
      score: 5,
      submittedAt: '2026-06-01T02:00:00.000Z',
    });
    await repos.challenges.upsertEntry({
      date: challenge.date,
      userId: beta.id,
      score: 30,
      submittedAt: '2026-06-01T03:00:00.000Z',
    });

    const board = await repos.challenges.leaderboard(challenge.date, 1, 0);
    expect(board.total).toBe(2);
    expect(board.entries[0]).toMatchObject({ username: beta.username, score: 30 });
    const second = await repos.challenges.leaderboard(challenge.date, 1, 1);
    expect(second.entries[0]).toMatchObject({ username: alpha.username, score: 20 });
  });
});
