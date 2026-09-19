/** `/v1/achievements` — catalog plus two-way sync for offline unlocks. */
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { getRepositories } from '../repositories/index.js';
import { ACHIEVEMENT_CODES, totalAchievementPoints } from '../domain/achievements.js';
import { badRequest } from '../utils/errors.js';

const syncSchema = z.object({
  achievements: z
    .array(
      z.object({
        code: z.string().min(1).max(64),
        progress: z.coerce.number().int().min(0).max(1_000_000).default(0),
        unlockedAt: z.string().datetime().optional().nullable(),
      }),
    )
    .min(1)
    .max(100),
});

export const achievementsRouter = Router();

achievementsRouter.get('/', async (_req: Request, res: Response) => {
  const catalog = await getRepositories().achievements.catalog();
  res.json({ items: catalog, total: catalog.length, totalPoints: totalAchievementPoints });
});

achievementsRouter.get('/me', requireAuth, async (req: Request, res: Response) => {
  const repos = getRepositories();
  const [catalog, mine] = await Promise.all([
    repos.achievements.catalog(),
    repos.achievements.forUser(req.user!.id),
  ]);
  const byCode = new Map(mine.map((entry) => [entry.code, entry]));

  const items = catalog.map((definition) => {
    const entry = byCode.get(definition.code);
    return {
      ...definition,
      progress: entry?.progress ?? 0,
      unlockedAt: entry?.unlockedAt ?? null,
      unlocked: Boolean(entry?.unlockedAt),
    };
  });

  const unlocked = items.filter((item) => item.unlocked);
  res.json({
    items,
    unlocked: unlocked.length,
    total: items.length,
    points: unlocked.reduce((sum, item) => sum + item.points, 0),
    totalPoints: totalAchievementPoints,
  });
});

/**
 * Merge client-side unlocks into the server state.
 *
 * Merge rules are monotonic — progress only ever increases and an unlock
 * timestamp is never overwritten — so replaying an old sync payload is harmless.
 */
achievementsRouter.post(
  '/me/sync',
  requireAuth,
  validate({ body: syncSchema }),
  async (req: Request, res: Response) => {
    const { achievements } = req.body as z.infer<typeof syncSchema>;
    const unknown = achievements.filter((entry) => !ACHIEVEMENT_CODES.has(entry.code));
    if (unknown.length > 0) {
      throw badRequest('Unknown achievement codes', {
        codes: unknown.map((entry) => entry.code),
      });
    }

    const saved = await getRepositories().achievements.upsertMany(
      achievements.map((entry) => ({
        userId: req.user!.id,
        code: entry.code,
        progress: entry.progress,
        unlockedAt: entry.unlockedAt ?? null,
      })),
    );
    res.json({ items: saved, synced: saved.length });
  },
);
