/** Persisted entities and public DTOs. */
import type { BirdSkin, GameMode, LeaderboardWindow } from '../config/constants.js';

export type UserRole = 'player' | 'admin';

export interface User {
  id: string;
  username: string;
  email: string | null;
  passwordHash: string | null;
  displayName: string;
  country: string | null;
  avatarSkin: BirdSkin;
  role: UserRole;
  isGuest: boolean;
  deviceId: string | null;
  isBanned: boolean;
  banReason: string | null;
  createdAt: string;
  updatedAt: string;
  lastSeenAt: string;
}

/** Everything safe to expose to other players. */
export interface PublicUser {
  id: string;
  username: string;
  displayName: string;
  country: string | null;
  avatarSkin: BirdSkin;
  isGuest: boolean;
  createdAt: string;
}

/** Adds private fields only the owner (or an admin) may read. */
export interface PrivateUser extends PublicUser {
  email: string | null;
  role: UserRole;
  lastSeenAt: string;
}

export interface RefreshTokenRecord {
  id: string;
  userId: string;
  tokenHash: string;
  expiresAt: string;
  revokedAt: string | null;
  userAgent: string | null;
  createdAt: string;
}

export interface Score {
  id: string;
  userId: string;
  score: number;
  mode: GameMode;
  coins: number;
  pipesPassed: number;
  durationMs: number;
  maxCombo: number;
  powerUpsUsed: number;
  seed: string;
  clientVersion: string | null;
  deviceModel: string | null;
  flagged: boolean;
  flagReason: string | null;
  submittedAt: string;
}

export interface NewScore extends Omit<Score, 'id' | 'submittedAt' | 'flagged' | 'flagReason'> {
  flagged?: boolean;
  flagReason?: string | null;
}

export interface UserStats {
  userId: string;
  bestScore: number;
  bestScoreMode: GameMode | null;
  totalScore: number;
  gamesPlayed: number;
  totalCoins: number;
  totalPipes: number;
  totalDurationMs: number;
  longestRunMs: number;
  bestCombo: number;
  updatedAt: string;
}

export interface AchievementDefinition {
  code: string;
  name: string;
  description: string;
  icon: string;
  points: number;
  /** `score`, `coins`, `games`, `pipes`, `combo`, `special` */
  metric: string;
  threshold: number;
  secret: boolean;
}

export interface UserAchievement {
  userId: string;
  code: string;
  progress: number;
  unlockedAt: string | null;
}

export type FriendshipStatus = 'active';

export interface Friendship {
  userId: string;
  friendId: string;
  status: FriendshipStatus;
  createdAt: string;
}

export interface DailyChallenge {
  date: string;
  seed: string;
  mode: GameMode;
  /** Vertical gap between pipes, in points. */
  pipeGap: number;
  /** Gravity multiplier applied on top of the base value. */
  gravityScale: number;
  /** Horizontal scroll multiplier. */
  speedScale: number;
  /** Extra modifier, e.g. `windy`, `foggy`, `nightfall`, `none`. */
  modifier: string;
  description: string;
  createdAt: string;
}

export interface ChallengeEntry {
  date: string;
  userId: string;
  score: number;
  submittedAt: string;
}

export interface LeaderboardEntry {
  rank: number;
  scoreId: string;
  userId: string;
  username: string;
  displayName: string;
  avatarSkin: BirdSkin;
  country: string | null;
  score: number;
  mode: GameMode;
  coins: number;
  pipesPassed: number;
  durationMs: number;
  achievedAt: string;
}

export interface LeaderboardQuery {
  mode: GameMode | null;
  window: LeaderboardWindow;
  limit: number;
  offset: number;
}

export function toPublicUser(user: User): PublicUser {
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    country: user.country,
    avatarSkin: user.avatarSkin,
    isGuest: user.isGuest,
    createdAt: user.createdAt,
  };
}

export function toPrivateUser(user: User): PrivateUser {
  return {
    ...toPublicUser(user),
    email: user.email,
    role: user.role,
    lastSeenAt: user.lastSeenAt,
  };
}

export function emptyStats(userId: string): UserStats {
  return {
    userId,
    bestScore: 0,
    bestScoreMode: null,
    totalScore: 0,
    gamesPlayed: 0,
    totalCoins: 0,
    totalPipes: 0,
    totalDurationMs: 0,
    longestRunMs: 0,
    bestCombo: 0,
    updatedAt: new Date().toISOString(),
  };
}
