/**
 * Score submission pipeline.
 *
 * 1. plausibility check (`antiCheat`);
 * 2. persist the run;
 * 3. fold it into the player's aggregate stats;
 * 4. evaluate stat-driven achievements;
 * 5. resolve the player's new rank and broadcast an SSE event.
 */
import type { GameMode } from '../config/constants.js';
import { evaluateStatAchievements } from '../domain/achievements.js';
import type {
  LeaderboardEntry,
  Score,
  User,
  UserAchievement,
  UserStats,
} from '../domain/models.js';
import { getRepositories } from '../repositories/index.js';
import { verifyRun, verifySubmissionRate, type RunSubmission } from './antiCheat.js';
import { eventHub } from './events.js';
import { MS_PER_MINUTE, utcDateKey } from '../utils/time.js';
import { deriveDailyChallenge } from '../domain/challenge.js';

export interface SubmitScoreInput extends RunSubmission {
  clientVersion: string | null;
  deviceModel: string | null;
}

export interface SubmitScoreResult {
  score: Score;
  stats: UserStats;
  unlockedAchievements: UserAchievement[];
  personalBest: boolean;
  rank: number | null;
  totalPlayers: number;
  flagged: boolean;
  flagReasons: string[];
}

export async function submitScore(user: User, input: SubmitScoreInput): Promise<SubmitScoreResult> {
  const repos = getRepositories();

  const verdict = verifyRun(input);
  const recentRuns = await repos.scores.countForUserSince(
    user.id,
    new Date(Date.now() - MS_PER_MINUTE).toISOString(),
  );
  const rateReason = verifySubmissionRate(recentRuns);
  const reasons = rateReason ? [...verdict.reasons, rateReason] : verdict.reasons;
  const flagged = reasons.length > 0;

  const previousStats = await repos.stats.get(user.id);
  const previousBest = previousStats?.bestScore ?? 0;

  const score = await repos.scores.insert({
    userId: user.id,
    score: input.score,
    mode: input.mode,
    coins: input.coins,
    pipesPassed: input.pipesPassed,
    durationMs: input.durationMs,
    maxCombo: input.maxCombo,
    powerUpsUsed: input.powerUpsUsed,
    seed: input.seed,
    clientVersion: input.clientVersion,
    deviceModel: input.deviceModel,
    flagged,
    flagReason: flagged ? reasons.join('; ') : null,
  });

  // Flagged runs never influence stats, leaderboards or achievements.
  const stats = flagged
    ? (previousStats ?? (await repos.stats.recompute(user.id)))
    : await repos.stats.applyScore(score);

  let unlocked: UserAchievement[] = [];
  if (!flagged) {
    const existing = await repos.achievements.forUser(user.id);
    const updates = evaluateStatAchievements(stats, existing);
    const saved = await repos.achievements.upsertMany(updates);
    const previouslyUnlocked = new Set(
      existing.filter((entry) => entry.unlockedAt).map((entry) => entry.code),
    );
    unlocked = saved.filter((entry) => entry.unlockedAt && !previouslyUnlocked.has(entry.code));
  }

  if (!flagged && input.mode === 'daily') {
    const date = utcDateKey();
    const challenge =
      (await repos.challenges.getByDate(date)) ??
      (await repos.challenges.create(deriveDailyChallenge(date)));
    await repos.challenges.upsertEntry({
      date: challenge.date,
      userId: user.id,
      score: input.score,
      submittedAt: new Date().toISOString(),
    });
  }

  const ranking = flagged
    ? null
    : await repos.scores.rankForUser(user.id, { mode: null, window: 'all' });

  if (!flagged) {
    eventHub.publish({
      type: 'score.submitted',
      at: new Date().toISOString(),
      payload: {
        username: user.username,
        score: score.score,
        mode: score.mode,
        rank: ranking?.entry.rank ?? null,
      },
    });
  }

  return {
    score,
    stats,
    unlockedAchievements: unlocked,
    personalBest: !flagged && score.score > previousBest,
    rank: ranking?.entry.rank ?? null,
    totalPlayers: ranking?.total ?? 0,
    flagged,
    flagReasons: reasons,
  };
}

export async function personalBest(userId: string, mode: GameMode | null): Promise<Score | null> {
  return getRepositories().scores.bestForUser(userId, mode);
}

export async function ownRank(
  userId: string,
  mode: GameMode | null,
  window: 'all' | 'daily' | 'weekly' | 'monthly',
): Promise<{ entry: LeaderboardEntry; total: number } | null> {
  return getRepositories().scores.rankForUser(userId, { mode, window });
}
