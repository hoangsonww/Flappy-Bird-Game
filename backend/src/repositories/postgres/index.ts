/**
 * Postgres storage driver.
 *
 * Ranking rules (shared with the in-memory driver):
 *  - only unflagged runs from unbanned users are eligible;
 *  - a player appears once, represented by their best run in the window;
 *  - ties are broken by the earliest submission, and tied players share a rank.
 */
import { closePool, query, transaction } from '../../db/pool.js';
import {
  type ChallengeEntry,
  type DailyChallenge,
  type Friendship,
  type LeaderboardQuery,
  type NewScore,
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
import {
  toAchievementDefinition,
  toChallenge,
  toFriendship,
  toLeaderboardEntry,
  toScore,
  toStats,
  toToken,
  toUser,
  toUserAchievement,
  type AchievementRow,
  type ChallengeRow,
  type FriendshipRow,
  type LeaderboardRow,
  type ScoreRow,
  type StatsRow,
  type TokenRow,
  type UserAchievementRow,
  type UserRow,
} from './rows.js';

const USER_COLUMNS = `id, username, email, password_hash, display_name, country, avatar_skin,
  role, is_guest, device_id, is_banned, ban_reason, created_at, updated_at, last_seen_at`;

const SCORE_COLUMNS = `id, user_id, score, mode, coins, pipes_passed, duration_ms, max_combo,
  power_ups_used, seed, client_version, device_model, flagged, flag_reason, submitted_at`;

const users: UserRepository = {
  async create(input: CreateUserInput): Promise<User> {
    try {
      const result = await query<UserRow>(
        `INSERT INTO users (id, username, username_lower, email, email_lower, password_hash,
           display_name, country, avatar_skin, role, is_guest, device_id)
         VALUES ($1, $2, lower($2), $3, lower($3), $4, $5, $6, $7, $8, $9, $10)
         RETURNING ${USER_COLUMNS}`,
        [
          newId(),
          input.username,
          input.email,
          input.passwordHash,
          input.displayName,
          input.country,
          input.avatarSkin,
          input.role ?? 'player',
          input.isGuest,
          input.deviceId,
        ],
      );
      return toUser(result.rows[0]!);
    } catch (error) {
      const pgError = error as { code?: string; constraint?: string };
      if (pgError.code === '23505') {
        if (pgError.constraint === 'users_username_lower_key') {
          throw conflict('Username is already taken', { field: 'username' });
        }
        if (pgError.constraint === 'users_email_lower_key') {
          throw conflict('Email is already registered', { field: 'email' });
        }
        if (pgError.constraint === 'users_device_id_key') {
          throw conflict('Device already has an account', { field: 'deviceId' });
        }
        throw conflict('Resource already exists');
      }
      throw error;
    }
  },

  async findById(id) {
    const result = await query<UserRow>(`SELECT ${USER_COLUMNS} FROM users WHERE id = $1`, [id]);
    return result.rows[0] ? toUser(result.rows[0]) : null;
  },

  async findByUsername(username) {
    const result = await query<UserRow>(
      `SELECT ${USER_COLUMNS} FROM users WHERE username_lower = lower($1)`,
      [username],
    );
    return result.rows[0] ? toUser(result.rows[0]) : null;
  },

  async findByEmail(email) {
    const result = await query<UserRow>(
      `SELECT ${USER_COLUMNS} FROM users WHERE email_lower = lower($1)`,
      [email],
    );
    return result.rows[0] ? toUser(result.rows[0]) : null;
  },

  async findByDeviceId(deviceId) {
    const result = await query<UserRow>(`SELECT ${USER_COLUMNS} FROM users WHERE device_id = $1`, [
      deviceId,
    ]);
    return result.rows[0] ? toUser(result.rows[0]) : null;
  },

  async findManyByIds(ids) {
    if (ids.length === 0) return [];
    const result = await query<UserRow>(
      `SELECT ${USER_COLUMNS} FROM users WHERE id = ANY($1::uuid[])`,
      [ids],
    );
    return result.rows.map(toUser);
  },

  async update(id, patch: UpdateUserInput) {
    const assignments: string[] = [];
    const params: unknown[] = [];
    const push = (column: string, value: unknown) => {
      params.push(value);
      assignments.push(`${column} = $${params.length}`);
    };

    if (patch.username !== undefined) {
      push('username', patch.username);
      push('username_lower', patch.username.toLowerCase());
    }
    if (patch.email !== undefined) {
      push('email', patch.email);
      push('email_lower', patch.email ? patch.email.toLowerCase() : null);
    }
    if (patch.passwordHash !== undefined) push('password_hash', patch.passwordHash);
    if (patch.displayName !== undefined) push('display_name', patch.displayName);
    if (patch.country !== undefined) push('country', patch.country);
    if (patch.avatarSkin !== undefined) push('avatar_skin', patch.avatarSkin);
    if (patch.isGuest !== undefined) push('is_guest', patch.isGuest);
    if (patch.isBanned !== undefined) push('is_banned', patch.isBanned);
    if (patch.banReason !== undefined) push('ban_reason', patch.banReason);

    if (assignments.length === 0) {
      const existing = await users.findById(id);
      if (!existing) throw notFound('User not found');
      return existing;
    }

    assignments.push('updated_at = now()');
    params.push(id);

    try {
      const result = await query<UserRow>(
        `UPDATE users SET ${assignments.join(', ')} WHERE id = $${params.length}
         RETURNING ${USER_COLUMNS}`,
        params,
      );
      if (!result.rows[0]) throw notFound('User not found');
      return toUser(result.rows[0]);
    } catch (error) {
      const pgError = error as { code?: string; constraint?: string };
      if (pgError.code === '23505' && pgError.constraint === 'users_username_lower_key') {
        throw conflict('Username is already taken', { field: 'username' });
      }
      if (pgError.code === '23505' && pgError.constraint === 'users_email_lower_key') {
        throw conflict('Email is already registered', { field: 'email' });
      }
      throw error;
    }
  },

  async remove(id) {
    await query('DELETE FROM users WHERE id = $1', [id]);
  },

  async search(queryText, limit) {
    const result = await query<UserRow>(
      `SELECT ${USER_COLUMNS} FROM users
       WHERE is_banned = FALSE
         AND (username_lower LIKE '%' || lower($1) || '%' OR lower(display_name) LIKE '%' || lower($1) || '%')
       ORDER BY username_lower ASC
       LIMIT $2`,
      [queryText, limit],
    );
    return result.rows.map(toUser);
  },

  async touchLastSeen(id) {
    await query('UPDATE users SET last_seen_at = now() WHERE id = $1', [id]);
  },

  async count() {
    const result = await query<{ count: string }>('SELECT COUNT(*)::text AS count FROM users');
    return Number(result.rows[0]?.count ?? 0);
  },
};

const tokens: TokenRepository = {
  async issue(input) {
    const result = await query<TokenRow>(
      `INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, user_agent)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, user_id, token_hash, expires_at, revoked_at, user_agent, created_at`,
      [newId(), input.userId, input.tokenHash, input.expiresAt, input.userAgent],
    );
    return toToken(result.rows[0]!);
  },

  async findByHash(tokenHash) {
    const result = await query<TokenRow>(
      `SELECT id, user_id, token_hash, expires_at, revoked_at, user_agent, created_at
       FROM refresh_tokens WHERE token_hash = $1`,
      [tokenHash],
    );
    return result.rows[0] ? toToken(result.rows[0]) : null;
  },

  async revoke(id) {
    await query(
      'UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL',
      [id],
    );
  },

  async revokeAllForUser(userId) {
    const result = await query(
      'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
      [userId],
    );
    return result.rowCount ?? 0;
  },

  async purgeExpired() {
    const result = await query('DELETE FROM refresh_tokens WHERE expires_at < now()');
    return result.rowCount ?? 0;
  },

  async countActiveForUser(userId) {
    const result = await query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM refresh_tokens
       WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > now()`,
      [userId],
    );
    return Number(result.rows[0]?.count ?? 0);
  },
};

/**
 * Shared ranking CTE.
 *
 * `$1` = mode filter (nullable), `$2` = window start (nullable timestamptz).
 * Additional parameters continue from `$3`.
 */
const RANKED_CTE = `
WITH eligible AS (
  SELECT DISTINCT ON (s.user_id)
    s.user_id, s.id AS score_id, s.score, s.mode, s.coins, s.pipes_passed,
    s.duration_ms, s.submitted_at
  FROM scores s
  JOIN users u ON u.id = s.user_id
  WHERE s.flagged = FALSE
    AND u.is_banned = FALSE
    AND ($1::text IS NULL OR s.mode = $1::text)
    AND ($2::timestamptz IS NULL OR s.submitted_at >= $2::timestamptz)
  ORDER BY s.user_id, s.score DESC, s.submitted_at ASC, s.seq ASC
),
ranked AS (
  -- RANK() orders by score alone so tied players share a rank (1, 1, 3 …).
  -- Row ordering applies submitted_at separately, so the earlier run shows first.
  SELECT e.*,
         RANK() OVER (ORDER BY e.score DESC) AS rank,
         COUNT(*) OVER () AS total
  FROM eligible e
)`;

const RANKED_SELECT = `
SELECT r.rank, r.total, r.score_id, r.user_id, u.username, u.display_name, u.avatar_skin,
       u.country, r.score, r.mode, r.coins, r.pipes_passed, r.duration_ms,
       r.submitted_at AS achieved_at
FROM ranked r
JOIN users u ON u.id = r.user_id`;

const scores: ScoreRepository = {
  async insert(input: NewScore): Promise<Score> {
    const result = await query<ScoreRow>(
      `INSERT INTO scores (id, user_id, score, mode, coins, pipes_passed, duration_ms, max_combo,
         power_ups_used, seed, client_version, device_model, flagged, flag_reason)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
       RETURNING ${SCORE_COLUMNS}`,
      [
        newId(),
        input.userId,
        input.score,
        input.mode,
        input.coins,
        input.pipesPassed,
        input.durationMs,
        input.maxCombo,
        input.powerUpsUsed,
        input.seed,
        input.clientVersion,
        input.deviceModel,
        input.flagged ?? false,
        input.flagReason ?? null,
      ],
    );
    return toScore(result.rows[0]!);
  },

  async findById(id) {
    const result = await query<ScoreRow>(`SELECT ${SCORE_COLUMNS} FROM scores WHERE id = $1`, [id]);
    return result.rows[0] ? toScore(result.rows[0]) : null;
  },

  async listByUser({ userId, limit, mode, before }) {
    const result = await query<ScoreRow>(
      `SELECT ${SCORE_COLUMNS} FROM scores
       WHERE user_id = $1
         AND ($2::text IS NULL OR mode = $2::text)
         AND ($3::timestamptz IS NULL OR submitted_at < $3::timestamptz)
       ORDER BY submitted_at DESC, seq DESC
       LIMIT $4`,
      [userId, mode, before, limit],
    );
    return result.rows.map(toScore);
  },

  async bestForUser(userId, mode) {
    const result = await query<ScoreRow>(
      `SELECT ${SCORE_COLUMNS} FROM scores
       WHERE user_id = $1 AND flagged = FALSE AND ($2::text IS NULL OR mode = $2::text)
       ORDER BY score DESC, submitted_at ASC, seq ASC
       LIMIT 1`,
      [userId, mode],
    );
    return result.rows[0] ? toScore(result.rows[0]) : null;
  },

  async countForUser(userId) {
    const result = await query<{ count: string }>(
      'SELECT COUNT(*)::text AS count FROM scores WHERE user_id = $1',
      [userId],
    );
    return Number(result.rows[0]?.count ?? 0);
  },

  async leaderboard(params: LeaderboardQuery) {
    const start = windowStart(params.window);
    const result = await query<LeaderboardRow>(
      `${RANKED_CTE} ${RANKED_SELECT}
       ORDER BY r.rank ASC, r.submitted_at ASC, u.username ASC
       LIMIT $3 OFFSET $4`,
      [params.mode, start ? start.toISOString() : null, params.limit, params.offset],
    );
    const total = result.rows[0] ? Number(result.rows[0].total ?? 0) : 0;
    return { entries: result.rows.map(toLeaderboardEntry), total };
  },

  async leaderboardForUserIds(userIds, params) {
    if (userIds.length === 0) return [];
    const start = windowStart(params.window);
    const result = await query<LeaderboardRow>(
      `${RANKED_CTE}, filtered AS (
         SELECT r.*, RANK() OVER (ORDER BY r.score DESC) AS friend_rank
         FROM ranked r WHERE r.user_id = ANY($3::uuid[])
       )
       SELECT f.friend_rank AS rank, f.total, f.score_id, f.user_id, u.username, u.display_name,
              u.avatar_skin, u.country, f.score, f.mode, f.coins, f.pipes_passed, f.duration_ms,
              f.submitted_at AS achieved_at
       FROM filtered f JOIN users u ON u.id = f.user_id
       ORDER BY f.friend_rank ASC, f.submitted_at ASC
       LIMIT $4`,
      [params.mode, start ? start.toISOString() : null, userIds, params.limit],
    );
    return result.rows.map(toLeaderboardEntry);
  },

  async rankForUser(userId, params) {
    const start = windowStart(params.window);
    const result = await query<LeaderboardRow>(
      `${RANKED_CTE} ${RANKED_SELECT} WHERE r.user_id = $3::uuid LIMIT 1`,
      [params.mode, start ? start.toISOString() : null, userId],
    );
    const row = result.rows[0];
    if (!row) return null;
    return { entry: toLeaderboardEntry(row), total: Number(row.total ?? 0) };
  },

  async neighboursForRank(params) {
    const start = windowStart(params.window);
    const from = Math.max(1, params.rank - params.radius);
    const to = params.rank + params.radius;
    const result = await query<LeaderboardRow>(
      `${RANKED_CTE} ${RANKED_SELECT} WHERE r.rank BETWEEN $3 AND $4 ORDER BY r.rank ASC LIMIT $5`,
      [params.mode, start ? start.toISOString() : null, from, to, params.limit],
    );
    return result.rows.map(toLeaderboardEntry);
  },

  async flag(id, reason) {
    await query('UPDATE scores SET flagged = TRUE, flag_reason = $2 WHERE id = $1', [id, reason]);
  },

  async remove(id) {
    await query('DELETE FROM scores WHERE id = $1', [id]);
  },

  async countAll() {
    const result = await query<{ count: string }>('SELECT COUNT(*)::text AS count FROM scores');
    return Number(result.rows[0]?.count ?? 0);
  },

  async countForUserSince(userId, since) {
    const result = await query<{ count: string }>(
      'SELECT COUNT(*)::text AS count FROM scores WHERE user_id = $1 AND submitted_at >= $2',
      [userId, since],
    );
    return Number(result.rows[0]?.count ?? 0);
  },
};

const STATS_COLUMNS = `user_id, best_score, best_score_mode, total_score, games_played, total_coins,
  total_pipes, total_duration_ms, longest_run_ms, best_combo, updated_at`;

const stats: StatsRepository = {
  async get(userId) {
    const result = await query<StatsRow>(
      `SELECT ${STATS_COLUMNS} FROM user_stats WHERE user_id = $1`,
      [userId],
    );
    return result.rows[0] ? toStats(result.rows[0]) : null;
  },

  async applyScore(score: Score): Promise<UserStats> {
    // Each column gets its own placeholder: reusing one parameter for both an
    // INTEGER and a BIGINT column makes Postgres refuse to deduce its type
    // ("inconsistent types deduced for parameter $n").
    const result = await query<StatsRow>(
      `INSERT INTO user_stats (user_id, best_score, best_score_mode, total_score, games_played,
         total_coins, total_pipes, total_duration_ms, longest_run_ms, best_combo, updated_at)
       VALUES ($1, $2, $3, $4, 1, $5, $6, $7, $8, $9, now())
       ON CONFLICT (user_id) DO UPDATE SET
         best_score        = GREATEST(user_stats.best_score, EXCLUDED.best_score),
         best_score_mode   = CASE WHEN EXCLUDED.best_score > user_stats.best_score
                                  THEN EXCLUDED.best_score_mode ELSE user_stats.best_score_mode END,
         total_score       = user_stats.total_score + EXCLUDED.total_score,
         games_played      = user_stats.games_played + 1,
         total_coins       = user_stats.total_coins + EXCLUDED.total_coins,
         total_pipes       = user_stats.total_pipes + EXCLUDED.total_pipes,
         total_duration_ms = user_stats.total_duration_ms + EXCLUDED.total_duration_ms,
         longest_run_ms    = GREATEST(user_stats.longest_run_ms, EXCLUDED.longest_run_ms),
         best_combo        = GREATEST(user_stats.best_combo, EXCLUDED.best_combo),
         updated_at        = now()
       RETURNING ${STATS_COLUMNS}`,
      [
        score.userId,
        score.score, // best_score      (integer)
        score.mode,
        score.score, // total_score     (bigint)
        score.coins, // total_coins     (bigint)
        score.pipesPassed, // total_pipes      (bigint)
        score.durationMs, // total_duration_ms (bigint)
        score.durationMs, // longest_run_ms   (integer)
        score.maxCombo,
      ],
    );
    return toStats(result.rows[0]!);
  },

  async recompute(userId) {
    const result = await query<StatsRow>(
      `INSERT INTO user_stats (user_id, best_score, best_score_mode, total_score, games_played,
         total_coins, total_pipes, total_duration_ms, longest_run_ms, best_combo, updated_at)
       SELECT $1,
              COALESCE(MAX(score), 0),
              (SELECT mode FROM scores WHERE user_id = $1 AND flagged = FALSE
                 ORDER BY score DESC, submitted_at ASC LIMIT 1),
              COALESCE(SUM(score), 0),
              COUNT(*),
              COALESCE(SUM(coins), 0),
              COALESCE(SUM(pipes_passed), 0),
              COALESCE(SUM(duration_ms), 0),
              COALESCE(MAX(duration_ms), 0),
              COALESCE(MAX(max_combo), 0),
              now()
       FROM scores WHERE user_id = $1 AND flagged = FALSE
       ON CONFLICT (user_id) DO UPDATE SET
         best_score        = EXCLUDED.best_score,
         best_score_mode   = EXCLUDED.best_score_mode,
         total_score       = EXCLUDED.total_score,
         games_played      = EXCLUDED.games_played,
         total_coins       = EXCLUDED.total_coins,
         total_pipes       = EXCLUDED.total_pipes,
         total_duration_ms = EXCLUDED.total_duration_ms,
         longest_run_ms    = EXCLUDED.longest_run_ms,
         best_combo        = EXCLUDED.best_combo,
         updated_at        = now()
       RETURNING ${STATS_COLUMNS}`,
      [userId],
    );
    return toStats(result.rows[0]!);
  },

  async topByMetric(metric, limit) {
    const column =
      metric === 'bestScore'
        ? 'best_score'
        : metric === 'totalCoins'
          ? 'total_coins'
          : 'games_played';
    const result = await query<StatsRow>(
      `SELECT ${STATS_COLUMNS} FROM user_stats ORDER BY ${column} DESC LIMIT $1`,
      [limit],
    );
    return result.rows.map(toStats);
  },

  async globalTotals() {
    const result = await query<{
      players: string;
      games: string;
      pipes: string;
      coins: string;
    }>(
      `SELECT (SELECT COUNT(*)::text FROM users) AS players,
              COALESCE(SUM(games_played), 0)::text AS games,
              COALESCE(SUM(total_pipes), 0)::text  AS pipes,
              COALESCE(SUM(total_coins), 0)::text  AS coins
       FROM user_stats`,
    );
    const row = result.rows[0];
    return {
      players: Number(row?.players ?? 0),
      games: Number(row?.games ?? 0),
      pipes: Number(row?.pipes ?? 0),
      coins: Number(row?.coins ?? 0),
    };
  },
};

const achievements: AchievementRepository = {
  async catalog() {
    const result = await query<AchievementRow>(
      `SELECT code, name, description, icon, points, metric, threshold, secret
       FROM achievements ORDER BY points ASC, code ASC`,
    );
    return result.rows.map(toAchievementDefinition);
  },

  async findDefinition(code) {
    const result = await query<AchievementRow>(
      `SELECT code, name, description, icon, points, metric, threshold, secret
       FROM achievements WHERE code = $1`,
      [code],
    );
    return result.rows[0] ? toAchievementDefinition(result.rows[0]) : null;
  },

  async forUser(userId) {
    const result = await query<UserAchievementRow>(
      'SELECT user_id, code, progress, unlocked_at FROM user_achievements WHERE user_id = $1',
      [userId],
    );
    return result.rows.map(toUserAchievement);
  },

  async upsert(input) {
    const result = await query<UserAchievementRow>(
      `INSERT INTO user_achievements (user_id, code, progress, unlocked_at)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, code) DO UPDATE SET
         progress    = GREATEST(user_achievements.progress, EXCLUDED.progress),
         unlocked_at = COALESCE(user_achievements.unlocked_at, EXCLUDED.unlocked_at)
       RETURNING user_id, code, progress, unlocked_at`,
      [input.userId, input.code, input.progress, input.unlockedAt],
    );
    return toUserAchievement(result.rows[0]!);
  },

  async upsertMany(inputs: UserAchievement[]) {
    if (inputs.length === 0) return [];
    return transaction(async (client) => {
      const saved: UserAchievement[] = [];
      for (const input of inputs) {
        const result = await client.query<UserAchievementRow>(
          `INSERT INTO user_achievements (user_id, code, progress, unlocked_at)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (user_id, code) DO UPDATE SET
             progress    = GREATEST(user_achievements.progress, EXCLUDED.progress),
             unlocked_at = COALESCE(user_achievements.unlocked_at, EXCLUDED.unlocked_at)
           RETURNING user_id, code, progress, unlocked_at`,
          [input.userId, input.code, input.progress, input.unlockedAt],
        );
        saved.push(toUserAchievement(result.rows[0]!));
      }
      return saved;
    });
  },
};

const friends: FriendRepository = {
  async list(userId) {
    const result = await query<FriendshipRow>(
      'SELECT user_id, friend_id, status, created_at FROM friendships WHERE user_id = $1 ORDER BY created_at DESC',
      [userId],
    );
    return result.rows.map(toFriendship);
  },

  async add(userId, friendId): Promise<Friendship> {
    const result = await query<FriendshipRow>(
      `INSERT INTO friendships (user_id, friend_id) VALUES ($1, $2)
       ON CONFLICT (user_id, friend_id) DO UPDATE SET status = 'active'
       RETURNING user_id, friend_id, status, created_at`,
      [userId, friendId],
    );
    return toFriendship(result.rows[0]!);
  },

  async remove(userId, friendId) {
    await query('DELETE FROM friendships WHERE user_id = $1 AND friend_id = $2', [
      userId,
      friendId,
    ]);
  },

  async exists(userId, friendId) {
    const result = await query<{ exists: boolean }>(
      'SELECT EXISTS (SELECT 1 FROM friendships WHERE user_id = $1 AND friend_id = $2) AS exists',
      [userId, friendId],
    );
    return Boolean(result.rows[0]?.exists);
  },
};

const CHALLENGE_COLUMNS = `date, seed, mode, pipe_gap, gravity_scale, speed_scale, modifier,
  description, created_at`;

const challenges: ChallengeRepository = {
  async getByDate(date) {
    const result = await query<ChallengeRow>(
      `SELECT ${CHALLENGE_COLUMNS} FROM daily_challenges WHERE date = $1::date`,
      [date],
    );
    return result.rows[0] ? toChallenge(result.rows[0]) : null;
  },

  async create(challenge: DailyChallenge) {
    const result = await query<ChallengeRow>(
      `INSERT INTO daily_challenges (date, seed, mode, pipe_gap, gravity_scale, speed_scale,
         modifier, description)
       VALUES ($1::date, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (date) DO UPDATE SET seed = EXCLUDED.seed
       RETURNING ${CHALLENGE_COLUMNS}`,
      [
        challenge.date,
        challenge.seed,
        challenge.mode,
        challenge.pipeGap,
        challenge.gravityScale,
        challenge.speedScale,
        challenge.modifier,
        challenge.description,
      ],
    );
    return toChallenge(result.rows[0]!);
  },

  async upsertEntry(entry: ChallengeEntry) {
    const result = await query<{ date: Date; user_id: string; score: number; submitted_at: Date }>(
      `INSERT INTO challenge_entries (date, user_id, score)
       VALUES ($1::date, $2, $3)
       ON CONFLICT (date, user_id) DO UPDATE SET
         score        = GREATEST(challenge_entries.score, EXCLUDED.score),
         submitted_at = CASE WHEN EXCLUDED.score > challenge_entries.score
                            THEN now() ELSE challenge_entries.submitted_at END
       RETURNING date, user_id, score, submitted_at`,
      [entry.date, entry.userId, entry.score],
    );
    const row = result.rows[0]!;
    return {
      date:
        row.date instanceof Date
          ? row.date.toISOString().slice(0, 10)
          : String(row.date).slice(0, 10),
      userId: row.user_id,
      score: Number(row.score),
      submittedAt: row.submitted_at.toISOString(),
    };
  },

  async leaderboard(date, limit, offset) {
    const result = await query<{
      date: Date;
      user_id: string;
      score: number;
      submitted_at: Date;
      username: string;
      display_name: string;
      avatar_skin: string;
      total: string;
    }>(
      `SELECT e.date, e.user_id, e.score, e.submitted_at, u.username, u.display_name, u.avatar_skin,
              COUNT(*) OVER () AS total
       FROM challenge_entries e
       JOIN users u ON u.id = e.user_id
       WHERE e.date = $1::date AND u.is_banned = FALSE
       ORDER BY e.score DESC, e.submitted_at ASC
       LIMIT $2 OFFSET $3`,
      [date, limit, offset],
    );

    return {
      total: result.rows[0] ? Number(result.rows[0].total) : 0,
      entries: result.rows.map((row) => ({
        date:
          row.date instanceof Date
            ? row.date.toISOString().slice(0, 10)
            : String(row.date).slice(0, 10),
        userId: row.user_id,
        score: Number(row.score),
        submittedAt: row.submitted_at.toISOString(),
        username: row.username,
        displayName: row.display_name,
        avatarSkin: row.avatar_skin as User['avatarSkin'],
      })),
    };
  },
};

export function createPostgresRepositories(): Repositories {
  return {
    driver: 'postgres',
    users,
    tokens,
    scores,
    stats,
    achievements,
    friends,
    challenges,
    async ping() {
      await query('SELECT 1');
    },
    async close() {
      await closePool();
    },
  };
}
