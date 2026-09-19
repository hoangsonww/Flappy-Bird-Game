/**
 * `/v1/admin` — moderation surface.
 *
 * Guarded by `requireAdmin`: either an account with `role = 'admin'` or a
 * request carrying `X-Admin-Token: $ADMIN_TOKEN`.
 */
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { optionalAuth, requireAdmin } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { getRepositories } from '../repositories/index.js';
import { notFound } from '../utils/errors.js';

export const adminRouter = Router();

adminRouter.use(optionalAuth, requireAdmin);

adminRouter.get('/stats', async (_req: Request, res: Response) => {
  const repos = getRepositories();
  const [users, runs, totals] = await Promise.all([
    repos.users.count(),
    repos.scores.countAll(),
    repos.stats.globalTotals(),
  ]);
  res.json({ users, runs, totals, driver: repos.driver });
});

adminRouter.post(
  '/users/:username/ban',
  validate({
    params: z.object({ username: z.string().min(3).max(20) }),
    body: z.object({
      reason: z.string().trim().min(3).max(200).default('Violated fair play rules'),
    }),
  }),
  async (req: Request, res: Response) => {
    const { username } = req.params as unknown as { username: string };
    const { reason } = req.body as { reason: string };
    const repos = getRepositories();
    const user = await repos.users.findByUsername(username);
    if (!user) throw notFound('Player not found');
    const updated = await repos.users.update(user.id, { isBanned: true, banReason: reason });
    await repos.tokens.revokeAllForUser(user.id);
    res.json({ user: { id: updated.id, username: updated.username, isBanned: updated.isBanned } });
  },
);

adminRouter.delete(
  '/users/:username/ban',
  validate({ params: z.object({ username: z.string().min(3).max(20) }) }),
  async (req: Request, res: Response) => {
    const { username } = req.params as unknown as { username: string };
    const repos = getRepositories();
    const user = await repos.users.findByUsername(username);
    if (!user) throw notFound('Player not found');
    const updated = await repos.users.update(user.id, { isBanned: false, banReason: null });
    res.json({ user: { id: updated.id, username: updated.username, isBanned: updated.isBanned } });
  },
);

adminRouter.post(
  '/scores/:id/flag',
  validate({
    params: z.object({ id: z.string().uuid() }),
    body: z.object({ reason: z.string().trim().min(3).max(200) }),
  }),
  async (req: Request, res: Response) => {
    const { id } = req.params as unknown as { id: string };
    const { reason } = req.body as { reason: string };
    const repos = getRepositories();
    const score = await repos.scores.findById(id);
    if (!score) throw notFound('Run not found');
    await repos.scores.flag(id, reason);
    await repos.stats.recompute(score.userId);
    res.json({ flagged: true, id, reason });
  },
);

adminRouter.delete(
  '/scores/:id',
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req: Request, res: Response) => {
    const { id } = req.params as unknown as { id: string };
    const repos = getRepositories();
    const score = await repos.scores.findById(id);
    if (!score) throw notFound('Run not found');
    await repos.scores.remove(id);
    await repos.stats.recompute(score.userId);
    res.status(204).end();
  },
);

adminRouter.post('/maintenance/purge-tokens', async (_req: Request, res: Response) => {
  const purged = await getRepositories().tokens.purgeExpired();
  res.json({ purged });
});

adminRouter.post(
  '/maintenance/recompute-stats/:username',
  validate({ params: z.object({ username: z.string().min(3).max(20) }) }),
  async (req: Request, res: Response) => {
    const { username } = req.params as unknown as { username: string };
    const repos = getRepositories();
    const user = await repos.users.findByUsername(username);
    if (!user) throw notFound('Player not found');
    res.json({ stats: await repos.stats.recompute(user.id) });
  },
);
