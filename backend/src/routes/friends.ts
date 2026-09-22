/** `/v1/friends` — a one-directional follow graph powering the friends board. */
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { USERNAME_PATTERN } from '../config/constants.js';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { getRepositories } from '../repositories/index.js';
import { asPublic } from '../services/userService.js';
import { badRequest, notFound } from '../utils/errors.js';

const usernameParam = z.object({
  username: z.string().trim().regex(USERNAME_PATTERN, 'Invalid username'),
});

export const friendsRouter = Router();

friendsRouter.get('/', requireAuth, async (req: Request, res: Response) => {
  const repos = getRepositories();
  const edges = await repos.friends.list(req.user!.id);
  const users = await repos.users.findManyByIds(edges.map((edge) => edge.friendId));
  const byId = new Map(users.map((user) => [user.id, user]));

  res.json({
    items: edges
      .map((edge) => {
        const friend = byId.get(edge.friendId);
        return friend ? { ...asPublic(friend), followedAt: edge.createdAt } : null;
      })
      .filter(Boolean),
    total: edges.length,
  });
});

friendsRouter.put(
  '/:username',
  requireAuth,
  validate({ params: usernameParam }),
  async (req: Request, res: Response) => {
    const { username } = req.params as unknown as z.infer<typeof usernameParam>;
    const repos = getRepositories();
    const target = await repos.users.findByUsername(username);
    if (!target || target.isBanned) throw notFound('Player not found');
    if (target.id === req.user!.id) throw badRequest('You cannot follow yourself');

    await repos.friends.add(req.user!.id, target.id);
    res.status(201).json({ friend: asPublic(target) });
  },
);

friendsRouter.delete(
  '/:username',
  requireAuth,
  validate({ params: usernameParam }),
  async (req: Request, res: Response) => {
    const { username } = req.params as unknown as z.infer<typeof usernameParam>;
    const repos = getRepositories();
    const target = await repos.users.findByUsername(username);
    if (!target) throw notFound('Player not found');
    await repos.friends.remove(req.user!.id, target.id);
    res.status(204).end();
  },
);
