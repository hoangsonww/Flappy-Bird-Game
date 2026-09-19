import type { AchievementDefinition, UserAchievement, UserStats } from './models.js';

/**
 * Canonical achievement catalog.
 *
 * The same list is mirrored in `FlappyBird/Systems/AchievementSystem.swift` so the
 * game can unlock achievements offline and reconcile with the server later.
 */
export const ACHIEVEMENTS: AchievementDefinition[] = [
  {
    code: 'first_flight',
    name: 'First Flight',
    description: 'Pass your first pipe.',
    icon: '🐣',
    points: 5,
    metric: 'score',
    threshold: 1,
    secret: false,
  },
  {
    code: 'getting_warm',
    name: 'Getting Warm',
    description: 'Score 10 in a single run.',
    icon: '🔥',
    points: 10,
    metric: 'score',
    threshold: 10,
    secret: false,
  },
  {
    code: 'sky_rookie',
    name: 'Sky Rookie',
    description: 'Score 25 in a single run.',
    icon: '🪶',
    points: 20,
    metric: 'score',
    threshold: 25,
    secret: false,
  },
  {
    code: 'pipe_dreamer',
    name: 'Pipe Dreamer',
    description: 'Score 50 in a single run.',
    icon: '🌤️',
    points: 40,
    metric: 'score',
    threshold: 50,
    secret: false,
  },
  {
    code: 'century',
    name: 'Century Club',
    description: 'Score 100 in a single run.',
    icon: '💯',
    points: 100,
    metric: 'score',
    threshold: 100,
    secret: false,
  },
  {
    code: 'legend',
    name: 'Living Legend',
    description: 'Score 200 in a single run.',
    icon: '👑',
    points: 250,
    metric: 'score',
    threshold: 200,
    secret: false,
  },
  {
    code: 'coin_collector',
    name: 'Coin Collector',
    description: 'Collect 100 coins in total.',
    icon: '🪙',
    points: 15,
    metric: 'coins',
    threshold: 100,
    secret: false,
  },
  {
    code: 'treasury',
    name: 'Treasury',
    description: 'Collect 1,000 coins in total.',
    icon: '💰',
    points: 60,
    metric: 'coins',
    threshold: 1000,
    secret: false,
  },
  {
    code: 'persistent',
    name: 'Persistent',
    description: 'Play 50 games.',
    icon: '🎮',
    points: 20,
    metric: 'games',
    threshold: 50,
    secret: false,
  },
  {
    code: 'dedicated',
    name: 'Dedicated',
    description: 'Play 250 games.',
    icon: '🏅',
    points: 75,
    metric: 'games',
    threshold: 250,
    secret: false,
  },
  {
    code: 'pipe_marathon',
    name: 'Pipe Marathon',
    description: 'Pass 1,000 pipes in total.',
    icon: '🏃',
    points: 50,
    metric: 'pipes',
    threshold: 1000,
    secret: false,
  },
  {
    code: 'combo_artist',
    name: 'Combo Artist',
    description: 'Reach a x10 combo.',
    icon: '✨',
    points: 35,
    metric: 'combo',
    threshold: 10,
    secret: false,
  },
  {
    code: 'untouchable',
    name: 'Untouchable',
    description: 'Reach a x25 combo.',
    icon: '⚡',
    points: 90,
    metric: 'combo',
    threshold: 25,
    secret: false,
  },
  {
    code: 'night_owl',
    name: 'Night Owl',
    description: 'Finish a run during the night cycle.',
    icon: '🌙',
    points: 15,
    metric: 'special',
    threshold: 1,
    secret: false,
  },
  {
    code: 'storm_chaser',
    name: 'Storm Chaser',
    description: 'Survive 30 seconds of wind.',
    icon: '🌪️',
    points: 30,
    metric: 'special',
    threshold: 1,
    secret: false,
  },
  {
    code: 'daily_devotee',
    name: 'Daily Devotee',
    description: 'Complete 7 daily challenges.',
    icon: '📅',
    points: 70,
    metric: 'special',
    threshold: 7,
    secret: false,
  },
  {
    code: 'perfect_start',
    name: 'Perfect Start',
    description: 'Pass 10 pipes without using a power-up.',
    icon: '🎯',
    points: 25,
    metric: 'special',
    threshold: 1,
    secret: false,
  },
  {
    code: 'ghost_rider',
    name: 'Ghost Rider',
    description: 'Beat your own ghost replay.',
    icon: '👻',
    points: 45,
    metric: 'special',
    threshold: 1,
    secret: true,
  },
];

export const ACHIEVEMENT_CODES = new Set(ACHIEVEMENTS.map((a) => a.code));

export const totalAchievementPoints = ACHIEVEMENTS.reduce((sum, a) => sum + a.points, 0);

/**
 * Server-side evaluation of stat-driven achievements.
 *
 * `special` achievements are client-driven (the game knows about weather, ghosts
 * and power-up usage) and arrive through `POST /v1/achievements/me/sync`.
 */
export function evaluateStatAchievements(
  stats: UserStats,
  existing: UserAchievement[],
): UserAchievement[] {
  const byCode = new Map(existing.map((entry) => [entry.code, entry]));
  const now = new Date().toISOString();
  const updates: UserAchievement[] = [];

  for (const definition of ACHIEVEMENTS) {
    if (definition.metric === 'special') continue;

    const progress = currentProgress(definition.metric, stats);
    const previous = byCode.get(definition.code);
    const alreadyUnlocked = Boolean(previous?.unlockedAt);
    const unlocked = progress >= definition.threshold;

    if (alreadyUnlocked && (previous?.progress ?? 0) >= progress) continue;

    updates.push({
      userId: stats.userId,
      code: definition.code,
      progress: Math.max(progress, previous?.progress ?? 0),
      unlockedAt: alreadyUnlocked ? (previous?.unlockedAt ?? now) : unlocked ? now : null,
    });
  }

  return updates;
}

function currentProgress(metric: string, stats: UserStats): number {
  switch (metric) {
    case 'score':
      return stats.bestScore;
    case 'coins':
      return stats.totalCoins;
    case 'games':
      return stats.gamesPlayed;
    case 'pipes':
      return stats.totalPipes;
    case 'combo':
      return stats.bestCombo;
    default:
      return 0;
  }
}
