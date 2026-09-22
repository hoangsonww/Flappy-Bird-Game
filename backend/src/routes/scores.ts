/** `/v1/scores` — run submission and personal history. */
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { GAME_MODES } from '../config/constants.js';
import { env } from '../config/env.js';
import { requireAuth } from '../middleware/auth.js';
import { submitLimiter } from '../middleware/rateLimit.js';
import { scoresSubmitted } from '../middleware/metrics.js';
import { validate } from '../middleware/validate.js';
import { getRepositories } from '../repositories/index.js';
import { submitScore } from '../services/scoreService.js';
import { forbidden, notFound } from '../utils/errors.js';

const submitSchema = z.object({
  score: z.coerce.number().int().min(0).max(env.MAX_SCORE),
  mode: z.enum(GAME_MODES).default('classic'),
  coins: z.coerce.number().int().min(0).max(100_000).default(0),
  pipesPassed: z.coerce.number().int().min(0).max(200_000).default(0),
  durationMs: z.coerce
    .number()
    .int()
    .min(0)
    .max(6 * 60 * 60 * 1000)
    .default(0),
  maxCombo: z.coerce.number().int().min(0).max(100_000).default(0),
  powerUpsUsed: z.coerce.number().int().min(0).max(1_000).default(0),
  seed: z.string().max(64).default(''),
  clientVersion: z.string().max(32).optional().nullable(),
  deviceModel: z.string().max(64).optional().nullable(),
  signature: z.string().max(128).optional().nullable(),
});

const historyQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(25),
  mode: z.enum(GAME_MODES).optional(),
  before: z.string().datetime().optional(),
});

export const scoresRouter = Router();

scoresRouter.post(
  '/',
  requireAuth,
  submitLimiter,
  validate({ body: submitSchema }),
  async (req: Request, res: Response) => {
    const input = req.body as z.infer<typeof submitSchema>;
    const result = await submitScore(req.user!, {
      ...input,
      clientVersion: input.clientVersion ?? null,
      deviceModel: input.deviceModel ?? null,
      signature: input.signature ?? null,
    });

    scoresSubmitted.inc({ mode: result.score.mode, flagged: String(result.flagged) });

    res.status(201).json({
      score: result.score,
      stats: result.stats,
      personalBest: result.personalBest,
      rank: result.rank,
      totalPlayers: result.totalPlayers,
      unlockedAchievements: result.unlockedAchievements,
      /** `true` means the run was stored but hidden from leaderboards. */
      flagged: result.flagged,
      flagReasons: result.flagReasons,
    });
  },
);

scoresRouter.get(
  '/me',
  requireAuth,
  validate({ query: historyQuery }),
  async (req: Request, res: Response) => {
    const { limit, mode, before } = req.query as unknown as z.infer<typeof historyQuery>;
    const items = await getRepositories().scores.listByUser({
      userId: req.user!.id,
      limit,
      mode: mode ?? null,
      before: before ?? null,
    });
    const nextBefore = items.length === limit ? items[items.length - 1]?.submittedAt : null;
    res.json({ items, limit, nextBefore });
  },
);

scoresRouter.get(
  '/me/best',
  requireAuth,
  validate({ query: z.object({ mode: z.enum(GAME_MODES).optional() }) }),
  async (req: Request, res: Response) => {
    const { mode } = req.query as unknown as { mode?: (typeof GAME_MODES)[number] };
    const best = await getRepositories().scores.bestForUser(req.user!.id, mode ?? null);
    res.json({ best });
  },
);

scoresRouter.get(
  '/:id',
  requireAuth,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req: Request, res: Response) => {
    const { id } = req.params as unknown as { id: string };
    const score = await getRepositories().scores.findById(id);
    if (!score) throw notFound('Run not found');
    if (score.userId !== req.user!.id && req.user!.role !== 'admin') {
      throw forbidden('You can only read your own runs');
    }
    res.json({ score });
  },
);
