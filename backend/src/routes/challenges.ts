/** `/v1/challenges` — the deterministic daily challenge and its board. */
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { deriveDailyChallenge } from '../domain/challenge.js';
import { getRepositories } from '../repositories/index.js';
import { env } from '../config/env.js';
import { utcDateKey } from '../utils/time.js';
import { badRequest } from '../utils/errors.js';

const dateParam = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Expected YYYY-MM-DD'),
});

const boardQuery = z.object({
  limit: z.coerce.number().int().min(1).max(env.LEADERBOARD_PAGE_MAX).default(25),
  offset: z.coerce.number().int().min(0).max(100_000).default(0),
});

const entrySchema = z.object({ score: z.coerce.number().int().min(0).max(env.MAX_SCORE) });

/** Fetch (or lazily materialise) the challenge for a date. */
async function ensureChallenge(date: string) {
  const repos = getRepositories();
  const existing = await repos.challenges.getByDate(date);
  if (existing) return existing;
  return repos.challenges.create(deriveDailyChallenge(date));
}

export const challengesRouter = Router();

challengesRouter.get('/today', async (_req: Request, res: Response) => {
  const date = utcDateKey();
  const challenge = await ensureChallenge(date);
  const nextRollover = new Date(`${date}T00:00:00.000Z`);
  nextRollover.setUTCDate(nextRollover.getUTCDate() + 1);
  res.json({ challenge, rollsOverAt: nextRollover.toISOString() });
});

challengesRouter.get(
  '/:date',
  validate({ params: dateParam }),
  async (req: Request, res: Response) => {
    const { date } = req.params as unknown as z.infer<typeof dateParam>;
    res.json({ challenge: await ensureChallenge(date) });
  },
);

challengesRouter.get(
  '/:date/leaderboard',
  validate({ params: dateParam, query: boardQuery }),
  async (req: Request, res: Response) => {
    const { date } = req.params as unknown as z.infer<typeof dateParam>;
    const { limit, offset } = req.query as unknown as z.infer<typeof boardQuery>;
    await ensureChallenge(date);
    const board = await getRepositories().challenges.leaderboard(date, limit, offset);
    res.json({
      date,
      items: board.entries.map((entry, index) => ({ rank: offset + index + 1, ...entry })),
      total: board.total,
      limit,
      offset,
      hasMore: offset + board.entries.length < board.total,
    });
  },
);

challengesRouter.post(
  '/today/entries',
  requireAuth,
  validate({ body: entrySchema }),
  async (req: Request, res: Response) => {
    const { score } = req.body as z.infer<typeof entrySchema>;
    const date = utcDateKey();
    await ensureChallenge(date);
    const entry = await getRepositories().challenges.upsertEntry({
      date,
      userId: req.user!.id,
      score,
      submittedAt: new Date().toISOString(),
    });
    res.status(201).json({ entry });
  },
);

challengesRouter.post(
  '/:date/entries',
  requireAuth,
  validate({ params: dateParam, body: entrySchema }),
  async (req: Request, res: Response) => {
    const { date } = req.params as unknown as z.infer<typeof dateParam>;
    if (date !== utcDateKey()) throw badRequest('Only today’s challenge accepts entries');
    const { score } = req.body as z.infer<typeof entrySchema>;
    await ensureChallenge(date);
    const entry = await getRepositories().challenges.upsertEntry({
      date,
      userId: req.user!.id,
      score,
      submittedAt: new Date().toISOString(),
    });
    res.status(201).json({ entry });
  },
);
