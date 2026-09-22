/**
 * In-memory storage driver.
 *
 * Purpose: let contributors run the full API (and the entire test suite) without
 * Docker or Postgres. Behaviour is intentionally identical to the Postgres
 * driver — the same repository contracts, the same ranking rules — so tests
 * written against one driver hold for the other.
 *
 * Data lives for the lifetime of the process only.
 */
import { ACHIEVEMENTS } from '../../domain/achievements.js';
import {
  emptyStats,
  type AchievementDefinition,
  type ChallengeEntry,
  type DailyChallenge,
  type Friendship,
  type LeaderboardEntry,
  type LeaderboardQuery,
  type NewScore,
  type RefreshTokenRecord,
  type Score,
  type User,
  type UserAchievement,
  type UserStats,
} from '../../domain/models.js';
import { conflict, notFound } from '../../utils/errors.js';
import { newId } from '../../utils/ids.js';
import { windowStart } from '../../utils/time.js';
import type {
  AchievementRepository,
  ChallengeRepository,
  CreateUserInput,
  FriendRepository,
  Repositories,
  ScoreRepository,
  StatsRepository,
  TokenRepository,
  UpdateUserInput,
  UserRepository,
} from '../types.js';

interface Store {
  users: Map<string, User>;
  tokens: Map<string, RefreshTokenRecord>;
  scores: Map<string, Score>;
  stats: Map<string, UserStats>;
  achievements: Map<string, UserAchievement>;
  friends: Map<string, Friendship>;
  challenges: Map<string, DailyChallenge>;
  challengeEntries: Map<string, ChallengeEntry>;
}

const store: Store = {
  users: new Map(),
  tokens: new Map(),
  scores: new Map(),
  stats: new Map(),
  achievements: new Map(),
  friends: new Map(),
  challenges: new Map(),
  challengeEntries: new Map(),
};

/** Test helper: wipe every collection. */
export function resetMemoryStore(): void {
  store.users.clear();
  store.tokens.clear();
  store.scores.clear();
  store.stats.clear();
  store.achievements.clear();
  store.friends.clear();
  store.challenges.clear();
  store.challengeEntries.clear();
  seqById.clear();
  sequence = 0;
}

const clone = <T>(value: T): T => structuredClone(value);

/**
 * Monotonic insertion counter mirroring the `scores.seq` column in Postgres.
 * Two runs stored in the same millisecond still have a stable relative order.
 */
let sequence = 0;
const seqById = new Map<string, number>();
const seqOf = (id: string): number => seqById.get(id) ?? 0;
const nowIso = () => new Date().toISOString();
const friendKey = (userId: string, friendId: string) => `${userId}:${friendId}`;
const achievementKey = (userId: string, code: string) => `${userId}:${code}`;
const entryKey = (date: string, userId: string) => `${date}:${userId}`;

const users: UserRepository = {
  async create(input: CreateUserInput): Promise<User> {
    for (const existing of store.users.values()) {
      if (existing.username.toLowerCase() === input.username.toLowerCase()) {
        throw conflict('Username is already taken', { field: 'username' });
      }
      if (
        input.email &&
        existing.email &&
        existing.email.toLowerCase() === input.email.toLowerCase()
      ) {
        throw conflict('Email is already registered', { field: 'email' });
      }
      if (input.deviceId && existing.deviceId === input.deviceId) {
        throw conflict('Device already has an account', { field: 'deviceId' });
      }
    }

    const timestamp = nowIso();
    const user: User = {
      id: newId(),
      username: input.username,
      email: input.email,
      passwordHash: input.passwordHash,
      displayName: input.displayName,
      country: input.country,
      avatarSkin: input.avatarSkin,
      role: input.role ?? 'player',
      isGuest: input.isGuest,
      deviceId: input.deviceId,
      isBanned: false,
      banReason: null,
      createdAt: timestamp,
      updatedAt: timestamp,
      lastSeenAt: timestamp,
    };
    store.users.set(user.id, user);
    store.stats.set(user.id, emptyStats(user.id));
    return clone(user);
  },

  async findById(id) {
    const user = store.users.get(id);
    return user ? clone(user) : null;
  },

  async findByUsername(username) {
    const lower = username.toLowerCase();
    for (const user of store.users.values()) {
      if (user.username.toLowerCase() === lower) return clone(user);
    }
    return null;
  },

  async findByEmail(email) {
    const lower = email.toLowerCase();
    for (const user of store.users.values()) {
      if (user.email && user.email.toLowerCase() === lower) return clone(user);
    }
    return null;
  },

  async findByDeviceId(deviceId) {
    for (const user of store.users.values()) {
      if (user.deviceId === deviceId) return clone(user);
    }
    return null;
  },

  async findManyByIds(ids) {
    return ids
      .map((id) => store.users.get(id))
      .filter((user): user is User => Boolean(user))
      .map(clone);
  },

  async update(id, patch: UpdateUserInput) {
    const user = store.users.get(id);
    if (!user) throw notFound('User not found');
    if (patch.username && patch.username.toLowerCase() !== user.username.toLowerCase()) {
      for (const other of store.users.values()) {
        if (other.id !== id && other.username.toLowerCase() === patch.username.toLowerCase()) {
          throw conflict('Username is already taken', { field: 'username' });
        }
      }
    }
    const updated: User = { ...user, ...patch, updatedAt: nowIso() };
    store.users.set(id, updated);
    return clone(updated);
  },

  async remove(id) {
    store.users.delete(id);
    store.stats.delete(id);
    for (const [key, score] of store.scores) if (score.userId === id) store.scores.delete(key);
    for (const [key, token] of store.tokens) if (token.userId === id) store.tokens.delete(key);
    for (const [key, ach] of store.achievements)
      if (ach.userId === id) store.achievements.delete(key);
    for (const [key, friend] of store.friends) {
      if (friend.userId === id || friend.friendId === id) store.friends.delete(key);
    }
    for (const [key, entry] of store.challengeEntries) {
      if (entry.userId === id) store.challengeEntries.delete(key);
    }
  },

  async search(query, limit) {
    const needle = query.toLowerCase();
    return [...store.users.values()]
      .filter(
        (user) =>
          !user.isBanned &&
          (user.username.toLowerCase().includes(needle) ||
            user.displayName.toLowerCase().includes(needle)),
      )
      .sort((a, b) => a.username.localeCompare(b.username))
      .slice(0, limit)
      .map(clone);
  },

  async touchLastSeen(id) {
    const user = store.users.get(id);
    if (user) store.users.set(id, { ...user, lastSeenAt: nowIso() });
  },

  async count() {
    return store.users.size;
  },
};

const tokens: TokenRepository = {
  async issue(input) {
    const record: RefreshTokenRecord = {
      id: newId(),
      userId: input.userId,
      tokenHash: input.tokenHash,
      expiresAt: input.expiresAt,
      revokedAt: null,
      userAgent: input.userAgent,
      createdAt: nowIso(),
    };
    store.tokens.set(record.id, record);
    return clone(record);
  },

  async findByHash(tokenHash) {
    for (const record of store.tokens.values()) {
      if (record.tokenHash === tokenHash) return clone(record);
    }
    return null;
  },

  async revoke(id) {
    const record = store.tokens.get(id);
    if (record) store.tokens.set(id, { ...record, revokedAt: nowIso() });
  },

  async revokeAllForUser(userId) {
    let count = 0;
    for (const [id, record] of store.tokens) {
      if (record.userId === userId && !record.revokedAt) {
        store.tokens.set(id, { ...record, revokedAt: nowIso() });
        count += 1;
      }
    }
    return count;
  },

  async purgeExpired() {
    const now = Date.now();
    let count = 0;
    for (const [id, record] of store.tokens) {
      if (Date.parse(record.expiresAt) < now) {
        store.tokens.delete(id);
        count += 1;
      }
    }
    return count;
  },

  async countActiveForUser(userId) {
    const now = Date.now();
    let count = 0;
    for (const record of store.tokens.values()) {
      if (record.userId === userId && !record.revokedAt && Date.parse(record.expiresAt) > now) {
        count += 1;
      }
    }
    return count;
  },
};

function eligibleScores(query: Pick<LeaderboardQuery, 'mode' | 'window'>): Score[] {
  const start = windowStart(query.window);
  return [...store.scores.values()].filter((score) => {
    if (score.flagged) return false;
    const user = store.users.get(score.userId);
    if (!user || user.isBanned) return false;
    if (query.mode && score.mode !== query.mode) return false;
    if (start && Date.parse(score.submittedAt) < start.getTime()) return false;
    return true;
  });
}

/** Best run per user, ranked by score then earliest submission (ties share a rank). */
function rankedBoard(query: Pick<LeaderboardQuery, 'mode' | 'window'>): LeaderboardEntry[] {
  const best = new Map<string, Score>();
  for (const score of eligibleScores(query)) {
    const current = best.get(score.userId);
    if (
      !current ||
      score.score > current.score ||
      (score.score === current.score &&
        (Date.parse(score.submittedAt) < Date.parse(current.submittedAt) ||
          (score.submittedAt === current.submittedAt && seqOf(score.id) < seqOf(current.id))))
    ) {
      best.set(score.userId, score);
    }
  }

  const sorted = [...best.values()].sort(
    (a, b) =>
      b.score - a.score ||
      Date.parse(a.submittedAt) - Date.parse(b.submittedAt) ||
      seqOf(a.id) - seqOf(b.id),
  );

  const board: LeaderboardEntry[] = [];
  let previousScore: number | null = null;
  let previousRank = 0;

  sorted.forEach((score, index) => {
    const user = store.users.get(score.userId)!;
    const rank = previousScore !== null && previousScore === score.score ? previousRank : index + 1;
    previousScore = score.score;
    previousRank = rank;

    board.push({
      rank,
      scoreId: score.id,
      userId: score.userId,
      username: user.username,
      displayName: user.displayName,
      avatarSkin: user.avatarSkin,
      country: user.country,
      score: score.score,
      mode: score.mode,
      coins: score.coins,
      pipesPassed: score.pipesPassed,
      durationMs: score.durationMs,
      achievedAt: score.submittedAt,
    });
  });

  return board;
}

const scores: ScoreRepository = {
  async insert(input: NewScore) {
    const score: Score = {
      ...input,
      id: newId(),
      flagged: input.flagged ?? false,
      flagReason: input.flagReason ?? null,
      submittedAt: nowIso(),
    };
    store.scores.set(score.id, score);
    sequence += 1;
    seqById.set(score.id, sequence);
    return clone(score);
  },

  async findById(id) {
    const score = store.scores.get(id);
    return score ? clone(score) : null;
  },

  async listByUser({ userId, limit, mode, before }) {
    return [...store.scores.values()]
      .filter((score) => score.userId === userId)
      .filter((score) => (mode ? score.mode === mode : true))
      .filter((score) => (before ? Date.parse(score.submittedAt) < Date.parse(before) : true))
      .sort(
        (a, b) =>
          Date.parse(b.submittedAt) - Date.parse(a.submittedAt) || seqOf(b.id) - seqOf(a.id),
      )
      .slice(0, limit)
      .map(clone);
  },

  async bestForUser(userId, mode) {
    const candidates = [...store.scores.values()]
      .filter((score) => score.userId === userId && !score.flagged)
      .filter((score) => (mode ? score.mode === mode : true))
      .sort(
        (a, b) =>
          b.score - a.score ||
          Date.parse(a.submittedAt) - Date.parse(b.submittedAt) ||
          seqOf(a.id) - seqOf(b.id),
      );
    return candidates[0] ? clone(candidates[0]) : null;
  },

  async countForUser(userId) {
    let count = 0;
    for (const score of store.scores.values()) if (score.userId === userId) count += 1;
    return count;
  },

  async leaderboard(query) {
    const board = rankedBoard(query);
    return {
      entries: board.slice(query.offset, query.offset + query.limit),
      total: board.length,
    };
  },

  async leaderboardForUserIds(userIds, query) {
    const allowed = new Set(userIds);
    const subset = rankedBoard(query).filter((entry) => allowed.has(entry.userId));

    // Re-rank within the subset, keeping the "ties share a rank" rule.
    let previousScore: number | null = null;
    let previousRank = 0;
    return subset.slice(0, query.limit).map((entry, index) => {
      const rank =
        previousScore !== null && previousScore === entry.score ? previousRank : index + 1;
      previousScore = entry.score;
      previousRank = rank;
      return { ...entry, rank };
    });
  },

  async rankForUser(userId, query) {
    const board = rankedBoard({ mode: query.mode, window: query.window });
    const entry = board.find((candidate) => candidate.userId === userId);
    return entry ? { entry, total: board.length } : null;
  },

  async neighboursForRank({ mode, window, rank, radius, limit }) {
    const board = rankedBoard({ mode, window });
    const index = board.findIndex((entry) => entry.rank === rank);
    const anchor = index >= 0 ? index : 0;
    const from = Math.max(0, anchor - radius);
    return board.slice(from, from + Math.min(limit, radius * 2 + 1));
  },

  async flag(id, reason) {
    const score = store.scores.get(id);
    if (score) store.scores.set(id, { ...score, flagged: true, flagReason: reason });
  },

  async remove(id) {
    store.scores.delete(id);
  },

  async countAll() {
    return store.scores.size;
  },

  async countForUserSince(userId, since) {
    const cutoff = Date.parse(since);
    let count = 0;
    for (const score of store.scores.values()) {
      if (score.userId === userId && Date.parse(score.submittedAt) >= cutoff) count += 1;
    }
    return count;
  },
};

const stats: StatsRepository = {
  async get(userId) {
    const record = store.stats.get(userId);
    return record ? clone(record) : null;
  },

  async applyScore(score) {
    const current = store.stats.get(score.userId) ?? emptyStats(score.userId);
    const next: UserStats = {
      userId: score.userId,
      bestScore: Math.max(current.bestScore, score.score),
      bestScoreMode: score.score > current.bestScore ? score.mode : current.bestScoreMode,
      totalScore: current.totalScore + score.score,
      gamesPlayed: current.gamesPlayed + 1,
      totalCoins: current.totalCoins + score.coins,
      totalPipes: current.totalPipes + score.pipesPassed,
      totalDurationMs: current.totalDurationMs + score.durationMs,
      longestRunMs: Math.max(current.longestRunMs, score.durationMs),
      bestCombo: Math.max(current.bestCombo, score.maxCombo),
      updatedAt: nowIso(),
    };
    store.stats.set(score.userId, next);
    return clone(next);
  },

  async recompute(userId) {
    const owned = [...store.scores.values()].filter((s) => s.userId === userId && !s.flagged);
    const next = owned.reduce<UserStats>((acc, score) => {
      acc.bestScore = Math.max(acc.bestScore, score.score);
      if (score.score >= acc.bestScore) acc.bestScoreMode = score.mode;
      acc.totalScore += score.score;
      acc.gamesPlayed += 1;
      acc.totalCoins += score.coins;
      acc.totalPipes += score.pipesPassed;
      acc.totalDurationMs += score.durationMs;
      acc.longestRunMs = Math.max(acc.longestRunMs, score.durationMs);
      acc.bestCombo = Math.max(acc.bestCombo, score.maxCombo);
      return acc;
    }, emptyStats(userId));
    next.updatedAt = nowIso();
    store.stats.set(userId, next);
    return clone(next);
  },

  async topByMetric(metric, limit) {
    return [...store.stats.values()]
      .sort((a, b) => (b[metric] as number) - (a[metric] as number))
      .slice(0, limit)
      .map(clone);
  },

  async globalTotals() {
    let games = 0;
    let pipes = 0;
    let coins = 0;
    for (const record of store.stats.values()) {
      games += record.gamesPlayed;
      pipes += record.totalPipes;
      coins += record.totalCoins;
    }
    return { players: store.users.size, games, pipes, coins };
  },
};

const achievements: AchievementRepository = {
  async catalog(): Promise<AchievementDefinition[]> {
    return ACHIEVEMENTS.map(clone);
  },

  async findDefinition(code) {
    const found = ACHIEVEMENTS.find((definition) => definition.code === code);
    return found ? clone(found) : null;
  },

  async forUser(userId) {
    return [...store.achievements.values()].filter((entry) => entry.userId === userId).map(clone);
  },

  async upsert(input) {
    const key = achievementKey(input.userId, input.code);
    const existing = store.achievements.get(key);
    const merged: UserAchievement = {
      userId: input.userId,
      code: input.code,
      progress: Math.max(existing?.progress ?? 0, input.progress),
      unlockedAt: existing?.unlockedAt ?? input.unlockedAt,
    };
    store.achievements.set(key, merged);
    return clone(merged);
  },

  async upsertMany(inputs) {
    const results: UserAchievement[] = [];
    for (const input of inputs) results.push(await achievements.upsert(input));
    return results;
  },
};

const friends: FriendRepository = {
  async list(userId) {
    return [...store.friends.values()].filter((edge) => edge.userId === userId).map(clone);
  },

  async add(userId, friendId) {
    const edge: Friendship = { userId, friendId, status: 'active', createdAt: nowIso() };
    store.friends.set(friendKey(userId, friendId), edge);
    return clone(edge);
  },

  async remove(userId, friendId) {
    store.friends.delete(friendKey(userId, friendId));
  },

  async exists(userId, friendId) {
    return store.friends.has(friendKey(userId, friendId));
  },
};

const challenges: ChallengeRepository = {
  async getByDate(date) {
    const challenge = store.challenges.get(date);
    return challenge ? clone(challenge) : null;
  },

  async create(challenge) {
    store.challenges.set(challenge.date, challenge);
    return clone(challenge);
  },

  async upsertEntry(entry) {
    const key = entryKey(entry.date, entry.userId);
    const existing = store.challengeEntries.get(key);
    if (!existing || entry.score > existing.score) {
      store.challengeEntries.set(key, entry);
      return clone(entry);
    }
    return clone(existing);
  },

  async leaderboard(date, limit, offset) {
    const all = [...store.challengeEntries.values()]
      .filter((entry) => entry.date === date)
      .filter((entry) => {
        const user = store.users.get(entry.userId);
        return Boolean(user) && !user!.isBanned;
      })
      .sort((a, b) => b.score - a.score || Date.parse(a.submittedAt) - Date.parse(b.submittedAt));

    return {
      total: all.length,
      entries: all.slice(offset, offset + limit).map((entry) => {
        const user = store.users.get(entry.userId)!;
        return {
          ...entry,
          username: user.username,
          displayName: user.displayName,
          avatarSkin: user.avatarSkin,
        };
      }),
    };
  },
};

export function createMemoryRepositories(): Repositories {
  return {
    driver: 'memory',
    users,
    tokens,
    scores,
    stats,
    achievements,
    friends,
    challenges,
    async ping() {
      /* always healthy */
    },
    async close() {
      /* nothing to close */
    },
  };
}
