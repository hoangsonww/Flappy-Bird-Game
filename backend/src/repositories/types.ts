/** Storage contracts. Implemented twice: Postgres (production) and in-memory (tests/demo). */
import type { GameMode } from '../config/constants.js';
import type {
  AchievementDefinition,
  ChallengeEntry,
  DailyChallenge,
  Friendship,
  LeaderboardEntry,
  LeaderboardQuery,
  NewScore,
  RefreshTokenRecord,
  Score,
  User,
  UserAchievement,
  UserStats,
} from '../domain/models.js';

export interface CreateUserInput {
  username: string;
  email: string | null;
  passwordHash: string | null;
  displayName: string;
  country: string | null;
  avatarSkin: User['avatarSkin'];
  isGuest: boolean;
  deviceId: string | null;
  role?: User['role'];
}

export type UpdateUserInput = Partial<
  Pick<
    User,
    | 'displayName'
    | 'country'
    | 'avatarSkin'
    | 'email'
    | 'passwordHash'
    | 'isBanned'
    | 'banReason'
    | 'username'
    | 'isGuest'
  >
>;

export interface UserRepository {
  create(input: CreateUserInput): Promise<User>;
  findById(id: string): Promise<User | null>;
  findByUsername(username: string): Promise<User | null>;
  findByEmail(email: string): Promise<User | null>;
  findByDeviceId(deviceId: string): Promise<User | null>;
  findManyByIds(ids: string[]): Promise<User[]>;
  update(id: string, patch: UpdateUserInput): Promise<User>;
  remove(id: string): Promise<void>;
  search(query: string, limit: number): Promise<User[]>;
  touchLastSeen(id: string): Promise<void>;
  count(): Promise<number>;
}

export interface TokenRepository {
  issue(input: {
    userId: string;
    tokenHash: string;
    expiresAt: string;
    userAgent: string | null;
  }): Promise<RefreshTokenRecord>;
  findByHash(tokenHash: string): Promise<RefreshTokenRecord | null>;
  revoke(id: string): Promise<void>;
  revokeAllForUser(userId: string): Promise<number>;
  purgeExpired(): Promise<number>;
  countActiveForUser(userId: string): Promise<number>;
}

export interface ScoreRepository {
  insert(input: NewScore): Promise<Score>;
  findById(id: string): Promise<Score | null>;
  listByUser(input: {
    userId: string;
    limit: number;
    mode: GameMode | null;
    before: string | null;
  }): Promise<Score[]>;
  bestForUser(userId: string, mode: GameMode | null): Promise<Score | null>;
  countForUser(userId: string): Promise<number>;
  leaderboard(query: LeaderboardQuery): Promise<{ entries: LeaderboardEntry[]; total: number }>;
  leaderboardForUserIds(
    userIds: string[],
    query: Omit<LeaderboardQuery, 'offset'>,
  ): Promise<LeaderboardEntry[]>;
  rankForUser(
    userId: string,
    query: Omit<LeaderboardQuery, 'limit' | 'offset'>,
  ): Promise<{ entry: LeaderboardEntry; total: number } | null>;
  neighboursForRank(
    query: LeaderboardQuery & { rank: number; radius: number },
  ): Promise<LeaderboardEntry[]>;
  flag(id: string, reason: string): Promise<void>;
  remove(id: string): Promise<void>;
  countAll(): Promise<number>;
  /** Number of runs submitted by a user since a timestamp — used by anti-cheat. */
  countForUserSince(userId: string, since: string): Promise<number>;
}

export interface StatsRepository {
  get(userId: string): Promise<UserStats | null>;
  applyScore(score: Score): Promise<UserStats>;
  recompute(userId: string): Promise<UserStats>;
  topByMetric(
    metric: 'bestScore' | 'totalCoins' | 'gamesPlayed',
    limit: number,
  ): Promise<UserStats[]>;
  globalTotals(): Promise<{ players: number; games: number; pipes: number; coins: number }>;
}

export interface AchievementRepository {
  catalog(): Promise<AchievementDefinition[]>;
  findDefinition(code: string): Promise<AchievementDefinition | null>;
  forUser(userId: string): Promise<UserAchievement[]>;
  upsert(input: UserAchievement): Promise<UserAchievement>;
  upsertMany(inputs: UserAchievement[]): Promise<UserAchievement[]>;
}

export interface FriendRepository {
  list(userId: string): Promise<Friendship[]>;
  add(userId: string, friendId: string): Promise<Friendship>;
  remove(userId: string, friendId: string): Promise<void>;
  exists(userId: string, friendId: string): Promise<boolean>;
}

export interface ChallengeRepository {
  getByDate(date: string): Promise<DailyChallenge | null>;
  create(challenge: DailyChallenge): Promise<DailyChallenge>;
  upsertEntry(entry: ChallengeEntry): Promise<ChallengeEntry>;
  leaderboard(
    date: string,
    limit: number,
    offset: number,
  ): Promise<{
    entries: Array<
      ChallengeEntry & { username: string; displayName: string; avatarSkin: User['avatarSkin'] }
    >;
    total: number;
  }>;
}

export interface Repositories {
  readonly driver: 'postgres' | 'memory';
  users: UserRepository;
  tokens: TokenRepository;
  scores: ScoreRepository;
  stats: StatsRepository;
  achievements: AchievementRepository;
  friends: FriendRepository;
  challenges: ChallengeRepository;
  /** Cheap liveness probe for /readyz. */
  ping(): Promise<void>;
  close(): Promise<void>;
}
