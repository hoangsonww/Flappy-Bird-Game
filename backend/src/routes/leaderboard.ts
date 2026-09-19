/** `/v1/leaderboard` — global, windowed, friends-only boards and a live SSE stream. */
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { GAME_MODES, LEADERBOARD_WINDOWS } from '../config/constants.js';
import { env } from '../config/env.js';
import { optionalAuth, requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { getRepositories } from '../repositories/index.js';
import { eventHub } from '../services/events.js';
import { forbidden } from '../utils/errors.js';

const boardQuery = z.object({
  mode: z.enum(GAME_MODES).optional(),
  window: z.enum(LEADERBOARD_WINDOWS).default('all'),
  limit: z.coerce.number().int().min(1).max(env.LEADERBOARD_PAGE_MAX).default(25),
  offset: z.coerce.number().int().min(0).max(100_000).default(0),
});

const meQuery = z.object({
  mode: z.enum(GAME_MODES).optional(),
  window: z.enum(LEADERBOARD_WINDOWS).default('all'),
  radius: z.coerce.number().int().min(0).max(25).default(3),
});

export const leaderboardRouter = Router();

leaderboardRouter.get(
  '/',
  optionalAuth,
  validate({ query: boardQuery }),
  async (req: Request, res: Response) => {
    const { mode, window, limit, offset } = req.query as unknown as z.infer<typeof boardQuery>;
    const { entries, total } = await getRepositories().scores.leaderboard({
      mode: mode ?? null,
      window,
      limit,
      offset,
    });

    res.json({
      window,
      mode: mode ?? 'all',
      items: entries,
      total,
      limit,
      offset,
      hasMore: offset + entries.length < total,
      generatedAt: new Date().toISOString(),
    });
  },
);

leaderboardRouter.get(
  '/me',
  requireAuth,
  validate({ query: meQuery }),
  async (req: Request, res: Response) => {
    const { mode, window, radius } = req.query as unknown as z.infer<typeof meQuery>;
    const repos = getRepositories();
    const ranking = await repos.scores.rankForUser(req.user!.id, { mode: mode ?? null, window });

    if (!ranking) {
      res.json({ window, mode: mode ?? 'all', rank: null, total: 0, entry: null, neighbours: [] });
      return;
    }

    const neighbours = await repos.scores.neighboursForRank({
      mode: mode ?? null,
      window,
      limit: radius * 2 + 1,
      offset: 0,
      rank: ranking.entry.rank,
      radius,
    });

    res.json({
      window,
      mode: mode ?? 'all',
      rank: ranking.entry.rank,
      total: ranking.total,
      entry: ranking.entry,
      neighbours,
    });
  },
);

leaderboardRouter.get(
  '/friends',
  requireAuth,
  validate({ query: boardQuery }),
  async (req: Request, res: Response) => {
    const { mode, window, limit } = req.query as unknown as z.infer<typeof boardQuery>;
    const repos = getRepositories();
    const friends = await repos.friends.list(req.user!.id);
    const ids = [req.user!.id, ...friends.map((edge) => edge.friendId)];
    const items = await repos.scores.leaderboardForUserIds(ids, {
      mode: mode ?? null,
      window,
      limit,
    });
    res.json({ window, mode: mode ?? 'all', items, total: items.length });
  },
);

/**
 * Live board updates over Server-Sent Events.
 *
 * The game subscribes while the leaderboard screen is open and falls back to
 * polling when the connection drops or the feature is disabled.
 */
leaderboardRouter.get('/stream', optionalAuth, (req: Request, res: Response) => {
  if (!env.ENABLE_SSE) throw forbidden('Live updates are disabled on this server');

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
  });

  const send = (event: { type: string; at: string; payload?: unknown }) => {
    res.write(`event: ${event.type}\n`);
    res.write(`data: ${JSON.stringify(event)}\n\n`);
  };

  send({ type: 'connected', at: new Date().toISOString() });

  const unsubscribe = eventHub.subscribe(send);
  const heartbeat = setInterval(() => {
    send({ type: 'heartbeat', at: new Date().toISOString() });
  }, 25_000);

  req.on('close', () => {
    clearInterval(heartbeat);
    unsubscribe();
    res.end();
  });
});
