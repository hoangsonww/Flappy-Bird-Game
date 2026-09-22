/** Shared, non-configurable constants. */

/** Semantic version of the HTTP contract exposed under /v1. */
export const API_VERSION = '1.0.0';

/** Capability flags advertised through `GET /v1/meta/config`.
 *  The iOS client uses these to decide which optional screens to show. */
export const CAPABILITIES = [
  'auth.password',
  'auth.guest',
  'auth.refresh',
  'scores.submit',
  'scores.history',
  'leaderboard.global',
  'leaderboard.windowed',
  'leaderboard.friends',
  'leaderboard.stream',
  'achievements.sync',
  'challenges.daily',
  'friends',
  'profiles',
  'stats',
] as const;

export type Capability = (typeof CAPABILITIES)[number];

/** Game modes accepted by the score endpoints. Mirrors `GameMode` in Swift. */
export const GAME_MODES = ['classic', 'endless', 'timeAttack', 'hardcore', 'zen', 'daily'] as const;
export type GameMode = (typeof GAME_MODES)[number];

/** Leaderboard time windows. */
export const LEADERBOARD_WINDOWS = ['all', 'daily', 'weekly', 'monthly'] as const;
export type LeaderboardWindow = (typeof LEADERBOARD_WINDOWS)[number];

/** Bird skins unlockable in game; validated when a profile is updated. */
export const BIRD_SKINS = [
  'classic',
  'midnight',
  'ember',
  'mint',
  'royal',
  'glitch',
  'aurora',
  'phoenix',
] as const;
export type BirdSkin = (typeof BIRD_SKINS)[number];

export const USERNAME_PATTERN = /^[a-zA-Z0-9_]{3,20}$/;
