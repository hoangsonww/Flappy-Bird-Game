import { describe, expect, it } from 'vitest';
import { evaluateStatAchievements, ACHIEVEMENTS } from '../src/domain/achievements.js';
import { deriveDailyChallenge } from '../src/domain/challenge.js';
import { emptyStats } from '../src/domain/models.js';
import { parseDuration, utcDateKey, windowStart } from '../src/utils/time.js';
import { decodeCursor, encodeCursor } from '../src/utils/pagination.js';
import { hashPassword, safeEqual, sha256, signRun, verifyPassword } from '../src/utils/crypto.js';
import { verifyRun } from '../src/services/antiCheat.js';

describe('time helpers', () => {
  it('formats a UTC date key', () => {
    expect(utcDateKey(new Date('2026-03-19T23:59:59Z'))).toBe('2026-03-19');
  });

  it('returns null for the all-time window', () => {
    expect(windowStart('all')).toBeNull();
  });

  it('starts the daily window at midnight UTC', () => {
    const start = windowStart('daily', new Date('2026-03-19T15:04:05Z'))!;
    expect(start.toISOString()).toBe('2026-03-19T00:00:00.000Z');
  });

  it('starts the weekly window on Monday', () => {
    // 2026-03-19 is a Thursday.
    const start = windowStart('weekly', new Date('2026-03-19T15:04:05Z'))!;
    expect(start.toISOString()).toBe('2026-03-16T00:00:00.000Z');
  });

  it('starts the monthly window on the first', () => {
    const start = windowStart('monthly', new Date('2026-03-19T15:04:05Z'))!;
    expect(start.toISOString()).toBe('2026-03-01T00:00:00.000Z');
  });

  it('parses compact durations', () => {
    expect(parseDuration('500ms')).toBe(500);
    expect(parseDuration('45s')).toBe(45_000);
    expect(parseDuration('15m')).toBe(900_000);
    expect(parseDuration('2h')).toBe(7_200_000);
    expect(parseDuration('30d')).toBe(2_592_000_000);
    expect(() => parseDuration('soon')).toThrow();
  });
});

describe('pagination cursors', () => {
  it('round-trips a payload', () => {
    const cursor = encodeCursor({ submittedAt: '2026-03-19T00:00:00.000Z', id: 'abc' });
    expect(decodeCursor(cursor)).toEqual({ submittedAt: '2026-03-19T00:00:00.000Z', id: 'abc' });
  });

  it('rejects a malformed cursor', () => {
    expect(() => decodeCursor('!!!not-base64!!!')).toThrow();
  });
});

describe('crypto helpers', () => {
  it('hashes and verifies a password', async () => {
    const hash = await hashPassword('flappybird123');
    expect(hash).not.toContain('flappybird123');
    expect(await verifyPassword('flappybird123', hash)).toBe(true);
    expect(await verifyPassword('wrong', hash)).toBe(false);
  });

  it('produces a stable sha256 digest', () => {
    expect(sha256('flappy')).toHaveLength(64);
    expect(sha256('flappy')).toBe(sha256('flappy'));
  });

  it('compares strings without leaking length mismatches', () => {
    expect(safeEqual('abc', 'abc')).toBe(true);
    expect(safeEqual('abc', 'abd')).toBe(false);
    expect(safeEqual('abc', 'abcd')).toBe(false);
  });

  it('signs a run deterministically from its canonical form', () => {
    const run = {
      mode: 'classic',
      score: 10,
      coins: 3,
      pipesPassed: 10,
      durationMs: 12_000,
      seed: 'x',
    };
    expect(signRun(run)).toBe(signRun(run));
    expect(signRun(run)).not.toBe(signRun({ ...run, score: 11 }));
  });
});

describe('achievement evaluation', () => {
  it('unlocks every threshold the stats have crossed', () => {
    const stats = { ...emptyStats('user-1'), bestScore: 30, totalCoins: 150, gamesPlayed: 60 };
    const updates = evaluateStatAchievements(stats, []);
    const unlocked = updates.filter((entry) => entry.unlockedAt).map((entry) => entry.code);

    expect(unlocked).toContain('first_flight');
    expect(unlocked).toContain('sky_rookie');
    expect(unlocked).toContain('coin_collector');
    expect(unlocked).toContain('persistent');
    expect(unlocked).not.toContain('century');
  });

  it('never re-unlocks or regresses an existing entry', () => {
    const stats = { ...emptyStats('user-1'), bestScore: 12 };
    const existing = [
      {
        userId: 'user-1',
        code: 'first_flight',
        progress: 99,
        unlockedAt: '2026-01-01T00:00:00.000Z',
      },
    ];
    const updates = evaluateStatAchievements(stats, existing);
    expect(updates.find((entry) => entry.code === 'first_flight')).toBeUndefined();
  });

  it('ignores client-driven special achievements', () => {
    const stats = { ...emptyStats('user-1'), bestScore: 500 };
    const codes = evaluateStatAchievements(stats, []).map((entry) => entry.code);
    const specials = ACHIEVEMENTS.filter((a) => a.metric === 'special').map((a) => a.code);
    for (const special of specials) expect(codes).not.toContain(special);
  });
});

describe('daily challenge derivation', () => {
  it('is deterministic per date', () => {
    const { createdAt: _a, ...first } = deriveDailyChallenge('2026-05-05');
    const { createdAt: _b, ...second } = deriveDailyChallenge('2026-05-05');
    expect(first).toEqual(second);
  });

  it('keeps every parameter inside the documented range', () => {
    for (let day = 1; day <= 28; day += 1) {
      const challenge = deriveDailyChallenge(`2026-02-${String(day).padStart(2, '0')}`);
      expect(challenge.pipeGap).toBeGreaterThanOrEqual(110);
      expect(challenge.pipeGap).toBeLessThanOrEqual(170);
      expect(challenge.gravityScale).toBeGreaterThanOrEqual(0.85);
      expect(challenge.gravityScale).toBeLessThanOrEqual(1.15);
      expect(challenge.speedScale).toBeGreaterThanOrEqual(0.9);
      expect(challenge.speedScale).toBeLessThanOrEqual(1.3);
      expect(challenge.description.length).toBeGreaterThan(0);
    }
  });
});

describe('anti-cheat verdicts', () => {
  const base = {
    mode: 'classic' as const,
    score: 20,
    coins: 8,
    pipesPassed: 20,
    durationMs: 26_000,
    maxCombo: 6,
    powerUpsUsed: 1,
    seed: 'seed',
  };

  it('accepts a plausible run', () => {
    expect(verifyRun(base)).toEqual({ outcome: 'accept', reasons: [] });
  });

  it('flags a run that is too fast for the pipe count', () => {
    const verdict = verifyRun({ ...base, durationMs: 500 });
    expect(verdict.outcome).toBe('flag');
    expect(verdict.reasons.join(' ')).toMatch(/too short/);
  });

  it('flags impossible coin counts and combos', () => {
    expect(verifyRun({ ...base, coins: 400 }).outcome).toBe('flag');
    expect(verifyRun({ ...base, maxCombo: 999 }).outcome).toBe('flag');
  });

  it('accepts a combo above the score, which coins alone can produce', () => {
    // Two coins taken from the first gaps, then a clipped pipe: score 0,
    // combo 2. Flagging this kept real early deaths off the leaderboard.
    const verdict = verifyRun({
      ...base,
      score: 0,
      pipesPassed: 0,
      coins: 2,
      maxCombo: 2,
      durationMs: 4_000,
    });
    expect(verdict).toEqual({ outcome: 'accept', reasons: [] });
  });

  it('flags a combo that more coins than were collected would be needed for', () => {
    const verdict = verifyRun({ ...base, coins: 2, maxCombo: 9 });
    expect(verdict.outcome).toBe('flag');
    expect(verdict.reasons.join(' ')).toMatch(/combo exceeds the coins/);
  });

  it('rejects a score above the pipes passed', () => {
    expect(() => verifyRun({ ...base, score: 50, pipesPassed: 10 })).toThrow();
  });

  it('allows time attack to score more than the pipes passed', () => {
    expect(() =>
      verifyRun({ ...base, mode: 'timeAttack', score: 50, pipesPassed: 10, durationMs: 60_000 }),
    ).not.toThrow();
  });

  it('flags a time attack run that outlasts the mode', () => {
    expect(verifyRun({ ...base, mode: 'timeAttack', durationMs: 120_000 }).outcome).toBe('flag');
  });

  it('flags a signature that does not match the payload', () => {
    const verdict = verifyRun({ ...base, signature: 'deadbeef' });
    expect(verdict.reasons.join(' ')).toMatch(/signature/);
  });

  it('accepts a correctly signed run', () => {
    expect(verifyRun({ ...base, signature: signRun(base) }).outcome).toBe('accept');
  });
});
