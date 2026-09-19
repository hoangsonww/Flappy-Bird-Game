/**
 * `/v1/auth` — registration, login, guest accounts, token rotation.
 *
 * Documented in `backend/openapi/openapi.yaml` (tag: Auth).
 */
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { BIRD_SKINS, USERNAME_PATTERN } from '../config/constants.js';
import { env } from '../config/env.js';
import { requireAuth } from '../middleware/auth.js';
import { authLimiter } from '../middleware/rateLimit.js';
import { validate } from '../middleware/validate.js';
import { accountsCreated } from '../middleware/metrics.js';
import { getRepositories } from '../repositories/index.js';
import {
  asPrivate,
  changePassword,
  login,
  loginOrCreateGuest,
  register,
  upgradeGuest,
} from '../services/userService.js';
import {
  issueTokenPair,
  revokeRefreshToken,
  rotateRefreshToken,
} from '../services/tokenService.js';
import { badRequest, forbidden } from '../utils/errors.js';

const usernameSchema = z
  .string()
  .trim()
  .regex(USERNAME_PATTERN, '3–20 characters, letters, digits and underscore only');

const passwordSchema = z
  .string()
  .min(8, 'Use at least 8 characters')
  .max(128, 'Use at most 128 characters');

const registerSchema = z.object({
  username: usernameSchema,
  password: passwordSchema,
  email: z.string().email().max(254).optional().nullable(),
  displayName: z.string().trim().min(1).max(40).optional().nullable(),
  country: z.string().trim().length(2).toUpperCase().optional().nullable(),
  avatarSkin: z.enum(BIRD_SKINS).optional(),
});

const loginSchema = z.object({
  username: z.string().trim().min(1).max(64),
  password: z.string().min(1).max(128),
});

const guestSchema = z.object({
  deviceId: z.string().trim().min(8).max(128),
  country: z.string().trim().length(2).toUpperCase().optional().nullable(),
});

const refreshSchema = z.object({ refreshToken: z.string().min(16).max(512) });

const passwordChangeSchema = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: passwordSchema,
});

const upgradeSchema = z.object({
  username: usernameSchema,
  password: passwordSchema,
  email: z.string().email().max(254).optional().nullable(),
  displayName: z.string().trim().min(1).max(40).optional().nullable(),
});

const userAgent = (req: Request): string | null => req.header('user-agent')?.slice(0, 200) ?? null;

export const authRouter = Router();

authRouter.post(
  '/register',
  authLimiter,
  validate({ body: registerSchema }),
  async (req: Request, res: Response) => {
    const input = req.body as z.infer<typeof registerSchema>;
    const user = await register(input);
    const tokens = await issueTokenPair(user, userAgent(req));
    accountsCreated.inc({ kind: 'password' });
    res.status(201).json({ user: asPrivate(user), tokens });
  },
);

authRouter.post(
  '/login',
  authLimiter,
  validate({ body: loginSchema }),
  async (req: Request, res: Response) => {
    const { username, password } = req.body as z.infer<typeof loginSchema>;
    const user = await login(username, password);
    const tokens = await issueTokenPair(user, userAgent(req));
    res.json({ user: asPrivate(user), tokens });
  },
);

authRouter.post(
  '/guest',
  authLimiter,
  validate({ body: guestSchema }),
  async (req: Request, res: Response) => {
    if (!env.ENABLE_GUEST_ACCOUNTS) throw forbidden('Guest accounts are disabled on this server');
    const { deviceId, country } = req.body as z.infer<typeof guestSchema>;
    const existing = await getRepositories().users.findByDeviceId(deviceId);
    const user = await loginOrCreateGuest(deviceId, country ?? null);
    const tokens = await issueTokenPair(user, userAgent(req));
    if (!existing) accountsCreated.inc({ kind: 'guest' });
    res.status(existing ? 200 : 201).json({ user: asPrivate(user), tokens });
  },
);

authRouter.post(
  '/refresh',
  validate({ body: refreshSchema }),
  async (req: Request, res: Response) => {
    const { refreshToken } = req.body as z.infer<typeof refreshSchema>;
    const { user, tokens } = await rotateRefreshToken(refreshToken, userAgent(req));
    res.json({ user: asPrivate(user), tokens });
  },
);

authRouter.post(
  '/logout',
  validate({ body: refreshSchema.partial() }),
  async (req: Request, res: Response) => {
    const { refreshToken } = req.body as { refreshToken?: string };
    if (refreshToken) await revokeRefreshToken(refreshToken);
    res.status(204).end();
  },
);

authRouter.post('/logout-all', requireAuth, async (req: Request, res: Response) => {
  const revoked = await getRepositories().tokens.revokeAllForUser(req.user!.id);
  res.json({ revoked });
});

authRouter.get('/me', requireAuth, async (req: Request, res: Response) => {
  const repos = getRepositories();
  const [stats, sessions] = await Promise.all([
    repos.stats.get(req.user!.id),
    repos.tokens.countActiveForUser(req.user!.id),
  ]);
  res.json({ user: asPrivate(req.user!), stats, activeSessions: sessions });
});

authRouter.patch(
  '/password',
  requireAuth,
  authLimiter,
  validate({ body: passwordChangeSchema }),
  async (req: Request, res: Response) => {
    const { currentPassword, newPassword } = req.body as z.infer<typeof passwordChangeSchema>;
    if (currentPassword === newPassword) {
      throw badRequest('The new password must differ from the current one');
    }
    await changePassword(req.user!, currentPassword, newPassword);
    res.status(204).end();
  },
);

authRouter.post(
  '/upgrade',
  requireAuth,
  authLimiter,
  validate({ body: upgradeSchema }),
  async (req: Request, res: Response) => {
    const input = req.body as z.infer<typeof upgradeSchema>;
    const user = await upgradeGuest(req.user!, input);
    const tokens = await issueTokenPair(user, userAgent(req));
    res.json({ user: asPrivate(user), tokens });
  },
);

authRouter.delete('/account', requireAuth, async (req: Request, res: Response) => {
  const repos = getRepositories();
  await repos.tokens.revokeAllForUser(req.user!.id);
  await repos.users.remove(req.user!.id);
  res.status(204).end();
});
