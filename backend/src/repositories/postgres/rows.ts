/** Row shapes returned by Postgres plus mappers to domain models. */
import type { BirdSkin, GameMode } from '../../config/constants.js';
import type {
  AchievementDefinition,
  DailyChallenge,
  Friendship,
  LeaderboardEntry,
  RefreshTokenRecord,
  Score,
  User,
  UserAchievement,
  UserStats,
} from '../../domain/models.js';

const iso = (value: Date | string | null): string =>
  value === null ? '' : value instanceof Date ? value.toISOString() : new Date(value).toISOString();

const isoOrNull = (value: Date | string | null): string | null =>
  value === null ? null : iso(value);

export interface UserRow {
  id: string;
  username: string;
  email: string | null;
  password_hash: string | null;
  display_name: string;
  country: string | null;
  avatar_skin: string;
  role: string;
  is_guest: boolean;
  device_id: string | null;
  is_banned: boolean;
  ban_reason: string | null;
  created_at: Date;
  updated_at: Date;
  last_seen_at: Date;
}

export const toUser = (row: UserRow): User => ({
  id: row.id,
  username: row.username,
  email: row.email,
  passwordHash: row.password_hash,
  displayName: row.display_name,
  country: row.country,
  avatarSkin: row.avatar_skin as BirdSkin,
  role: row.role === 'admin' ? 'admin' : 'player',
  isGuest: row.is_guest,
  deviceId: row.device_id,
  isBanned: row.is_banned,
  banReason: row.ban_reason,
  createdAt: iso(row.created_at),
  updatedAt: iso(row.updated_at),
  lastSeenAt: iso(row.last_seen_at),
});

export interface TokenRow {
  id: string;
  user_id: string;
  token_hash: string;
  expires_at: Date;
  revoked_at: Date | null;
  user_agent: string | null;
  created_at: Date;
}

export const toToken = (row: TokenRow): RefreshTokenRecord => ({
  id: row.id,
  userId: row.user_id,
  tokenHash: row.token_hash,
  expiresAt: iso(row.expires_at),
  revokedAt: isoOrNull(row.revoked_at),
  userAgent: row.user_agent,
  createdAt: iso(row.created_at),
});

export interface ScoreRow {
  id: string;
  user_id: string;
  score: number;
  mode: string;
  coins: number;
  pipes_passed: number;
  duration_ms: number;
  max_combo: number;
  power_ups_used: number;
  seed: string;
  client_version: string | null;
  device_model: string | null;
  flagged: boolean;
  flag_reason: string | null;
  submitted_at: Date;
}

export const toScore = (row: ScoreRow): Score => ({
  id: row.id,
  userId: row.user_id,
  score: Number(row.score),
  mode: row.mode as GameMode,
  coins: Number(row.coins),
  pipesPassed: Number(row.pipes_passed),
  durationMs: Number(row.duration_ms),
  maxCombo: Number(row.max_combo),
  powerUpsUsed: Number(row.power_ups_used),
  seed: row.seed,
  clientVersion: row.client_version,
  deviceModel: row.device_model,
  flagged: row.flagged,
  flagReason: row.flag_reason,
  submittedAt: iso(row.submitted_at),
});

export interface StatsRow {
  user_id: string;
  best_score: number;
  best_score_mode: string | null;
  total_score: string | number;
  games_played: number;
  total_coins: string | number;
  total_pipes: string | number;
  total_duration_ms: string | number;
  longest_run_ms: number;
  best_combo: number;
  updated_at: Date;
}

export const toStats = (row: StatsRow): UserStats => ({
  userId: row.user_id,
  bestScore: Number(row.best_score),
  bestScoreMode: (row.best_score_mode as GameMode | null) ?? null,
  totalScore: Number(row.total_score),
  gamesPlayed: Number(row.games_played),
  totalCoins: Number(row.total_coins),
  totalPipes: Number(row.total_pipes),
  totalDurationMs: Number(row.total_duration_ms),
  longestRunMs: Number(row.longest_run_ms),
  bestCombo: Number(row.best_combo),
  updatedAt: iso(row.updated_at),
});

export interface AchievementRow {
  code: string;
  name: string;
  description: string;
  icon: string;
  points: number;
  metric: string;
  threshold: number;
  secret: boolean;
}

export const toAchievementDefinition = (row: AchievementRow): AchievementDefinition => ({
  code: row.code,
  name: row.name,
  description: row.description,
  icon: row.icon,
  points: Number(row.points),
  metric: row.metric,
  threshold: Number(row.threshold),
  secret: row.secret,
});

export interface UserAchievementRow {
  user_id: string;
  code: string;
  progress: number;
  unlocked_at: Date | null;
}

export const toUserAchievement = (row: UserAchievementRow): UserAchievement => ({
  userId: row.user_id,
  code: row.code,
  progress: Number(row.progress),
  unlockedAt: isoOrNull(row.unlocked_at),
});

export interface FriendshipRow {
  user_id: string;
  friend_id: string;
  status: string;
  created_at: Date;
}

export const toFriendship = (row: FriendshipRow): Friendship => ({
  userId: row.user_id,
  friendId: row.friend_id,
  status: 'active',
  createdAt: iso(row.created_at),
});

export interface ChallengeRow {
  date: Date | string;
  seed: string;
  mode: string;
  pipe_gap: number;
  gravity_scale: string | number;
  speed_scale: string | number;
  modifier: string;
  description: string;
  created_at: Date;
}

export const toChallenge = (row: ChallengeRow): DailyChallenge => ({
  date: typeof row.date === 'string' ? row.date.slice(0, 10) : row.date.toISOString().slice(0, 10),
  seed: row.seed,
  mode: row.mode as GameMode,
  pipeGap: Number(row.pipe_gap),
  gravityScale: Number(row.gravity_scale),
  speedScale: Number(row.speed_scale),
  modifier: row.modifier,
  description: row.description,
  createdAt: iso(row.created_at),
});

export interface LeaderboardRow {
  rank: string | number;
  total?: string | number;
  score_id: string;
  user_id: string;
  username: string;
  display_name: string;
  avatar_skin: string;
  country: string | null;
  score: number;
  mode: string;
  coins: number;
  pipes_passed: number;
  duration_ms: number;
  achieved_at: Date;
}

export const toLeaderboardEntry = (row: LeaderboardRow): LeaderboardEntry => ({
  rank: Number(row.rank),
  scoreId: row.score_id,
  userId: row.user_id,
  username: row.username,
  displayName: row.display_name,
  avatarSkin: row.avatar_skin as BirdSkin,
  country: row.country,
  score: Number(row.score),
  mode: row.mode as GameMode,
  coins: Number(row.coins),
  pipesPassed: Number(row.pipes_passed),
  durationMs: Number(row.duration_ms),
  achievedAt: iso(row.achieved_at),
});
