/**
 * `/v1/meta` — service discovery.
 *
 * The iOS client probes `GET /v1/meta/config` at launch. A well-formed response
 * switches the game into "online mode"; anything else keeps it fully offline.
 */
import { Router, type Request, type Response } from 'express';
import {
  API_VERSION,
  BIRD_SKINS,
  CAPABILITIES,
  GAME_MODES,
  LEADERBOARD_WINDOWS,
} from '../config/constants.js';
import { env } from '../config/env.js';
import { getRepositories } from '../repositories/index.js';
import { totalAchievementPoints } from '../domain/achievements.js';

export const metaRouter = Router();

const startedAt = new Date();

metaRouter.get('/config', (_req: Request, res: Response) => {
  res.json({
    service: 'flappy-bird-backend',
    apiVersion: API_VERSION,
    /** Stable marker the game looks for before enabling online features. */
    protocol: 'flappy-bird/1',
    environment: env.NODE_ENV,
    capabilities: CAPABILITIES.filter((capability) => {
      if (capability === 'auth.guest') return env.ENABLE_GUEST_ACCOUNTS;
      if (capability === 'leaderboard.stream') return env.ENABLE_SSE;
      return true;
    }),
    limits: {
      maxScore: env.MAX_SCORE,
      leaderboardPageMax: env.LEADERBOARD_PAGE_MAX,
      rateLimitPerWindow: env.RATE_LIMIT_MAX,
      rateLimitWindowMs: env.RATE_LIMIT_WINDOW_MS,
    },
    gameModes: GAME_MODES,
    leaderboardWindows: LEADERBOARD_WINDOWS,
    birdSkins: BIRD_SKINS,
    achievementPointsTotal: totalAchievementPoints,
    requiresSignedRuns: env.REQUIRE_SIGNED_RUNS,
    docs: env.ENABLE_DOCS ? `${env.publicUrl}/docs` : null,
    startedAt: startedAt.toISOString(),
  });
});

metaRouter.get('/stats', async (_req: Request, res: Response) => {
  const repos = getRepositories();
  const [totals, runs] = await Promise.all([repos.stats.globalTotals(), repos.scores.countAll()]);
  res.json({
    players: totals.players,
    runsRecorded: runs,
    gamesPlayed: totals.games,
    pipesPassed: totals.pipes,
    coinsCollected: totals.coins,
    uptimeSeconds: Math.round(process.uptime()),
  });
});
