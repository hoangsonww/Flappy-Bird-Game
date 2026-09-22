/** `/v1/users` — public profiles, profile editing, player search. */
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { BIRD_SKINS, USERNAME_PATTERN } from '../config/constants.js';
import { optionalAuth, requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { getRepositories } from '../repositories/index.js';
import { asPrivate, asPublic, publicProfile, updateProfile } from '../services/userService.js';
import { notFound } from '../utils/errors.js';

const usernameParam = z.object({
  username: z.string().trim().regex(USERNAME_PATTERN, 'Invalid username'),
});

const searchQuery = z.object({
  q: z.string().trim().min(1).max(40),
  limit: z.coerce.number().int().min(1).max(50).default(10),
});

const profilePatch = z
  .object({
    displayName: z.string().trim().min(1).max(40).optional(),
    country: z.string().trim().length(2).toUpperCase().nullable().optional(),
    avatarSkin: z.enum(BIRD_SKINS).optional(),
  })
  .refine((value) => Object.keys(value).length > 0, { message: 'Provide at least one field' });

export const usersRouter = Router();

usersRouter.get('/me', requireAuth, async (req: Request, res: Response) => {
  const profile = await publicProfile(req.user!.username);
  res.json({ ...profile, user: asPrivate(req.user!) });
});

usersRouter.patch(
  '/me',
  requireAuth,
  validate({ body: profilePatch }),
  async (req: Request, res: Response) => {
    const patch = req.body as z.infer<typeof profilePatch>;
    const user = await updateProfile(req.user!, patch);
    res.json({ user: asPrivate(user) });
  },
);

usersRouter.get('/me/stats', requireAuth, async (req: Request, res: Response) => {
  const repos = getRepositories();
  const [stats, runs, best, rank] = await Promise.all([
    repos.stats.get(req.user!.id),
    repos.scores.countForUser(req.user!.id),
    repos.scores.bestForUser(req.user!.id, null),
    repos.scores.rankForUser(req.user!.id, { mode: null, window: 'all' }),
  ]);
  res.json({
    stats,
    runsRecorded: runs,
    best,
    rank: rank?.entry.rank ?? null,
    totalPlayers: rank?.total ?? 0,
  });
});

usersRouter.get(
  '/search',
  optionalAuth,
  validate({ query: searchQuery }),
  async (req: Request, res: Response) => {
    const { q, limit } = req.query as unknown as z.infer<typeof searchQuery>;
    const users = await getRepositories().users.search(q, limit);
    res.json({ items: users.map(asPublic), total: users.length });
  },
);

usersRouter.get(
  '/:username',
  optionalAuth,
  validate({ params: usernameParam }),
  async (req: Request, res: Response) => {
    const { username } = req.params as unknown as z.infer<typeof usernameParam>;
    const profile = await publicProfile(username);
    res.json(profile);
  },
);

usersRouter.get(
  '/:username/scores',
  optionalAuth,
  validate({
    params: usernameParam,
    query: z.object({ limit: z.coerce.number().int().min(1).max(50).default(10) }),
  }),
  async (req: Request, res: Response) => {
    const { username } = req.params as unknown as z.infer<typeof usernameParam>;
    const { limit } = req.query as unknown as { limit: number };
    const repos = getRepositories();
    const user = await repos.users.findByUsername(username);
    if (!user || user.isBanned) throw notFound('Player not found');
    const scores = await repos.scores.listByUser({
      userId: user.id,
      limit,
      mode: null,
      before: null,
    });
    res.json({ items: scores.filter((score) => !score.flagged), total: scores.length });
  },
);
