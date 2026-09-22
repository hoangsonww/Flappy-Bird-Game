/** Registration, login, guest accounts, profile updates. */
import { BIRD_SKINS, type BirdSkin } from '../config/constants.js';
import type { PrivateUser, PublicUser, User, UserStats } from '../domain/models.js';
import { toPrivateUser, toPublicUser } from '../domain/models.js';
import { getRepositories } from '../repositories/index.js';
import { hashPassword, verifyPassword } from '../utils/crypto.js';
import { conflict, forbidden, invalidCredentials, notFound } from '../utils/errors.js';
import { newShortCode } from '../utils/ids.js';

export interface RegisterInput {
  username: string;
  password: string;
  email?: string | null;
  displayName?: string | null;
  country?: string | null;
  avatarSkin?: BirdSkin;
}

export async function register(input: RegisterInput): Promise<User> {
  const repos = getRepositories();
  if (input.email) {
    const existing = await repos.users.findByEmail(input.email);
    if (existing) throw conflict('Email is already registered', { field: 'email' });
  }

  return repos.users.create({
    username: input.username,
    email: input.email ?? null,
    passwordHash: await hashPassword(input.password),
    displayName: input.displayName?.trim() || input.username,
    country: input.country ?? null,
    avatarSkin: input.avatarSkin ?? 'classic',
    isGuest: false,
    deviceId: null,
  });
}

export async function login(username: string, password: string): Promise<User> {
  const repos = getRepositories();
  const user = await repos.users.findByUsername(username);
  if (!user || !user.passwordHash) throw invalidCredentials();
  if (!(await verifyPassword(password, user.passwordHash))) throw invalidCredentials();
  if (user.isBanned) throw forbidden(user.banReason ?? 'This account is suspended');
  await repos.users.touchLastSeen(user.id);
  return user;
}

/**
 * Device-bound guest account.
 *
 * The game can start syncing scores before the player decides to pick a
 * username/password. Calling this twice with the same `deviceId` returns the
 * existing account instead of creating a duplicate.
 */
export async function loginOrCreateGuest(deviceId: string, country: string | null): Promise<User> {
  const repos = getRepositories();
  const existing = await repos.users.findByDeviceId(deviceId);
  if (existing) {
    if (existing.isBanned) throw forbidden(existing.banReason ?? 'This account is suspended');
    await repos.users.touchLastSeen(existing.id);
    return existing;
  }

  for (let attempt = 0; attempt < 5; attempt += 1) {
    const username = `guest_${newShortCode(6).toLowerCase()}`;
    const taken = await repos.users.findByUsername(username);
    if (taken) continue;
    return repos.users.create({
      username,
      email: null,
      passwordHash: null,
      displayName: 'Guest Flapper',
      country,
      avatarSkin: 'classic',
      isGuest: true,
      deviceId,
    });
  }
  throw conflict('Could not allocate a guest username, please retry');
}

/** Promote a guest into a full account, keeping their scores and achievements. */
export async function upgradeGuest(
  user: User,
  input: { username: string; password: string; email?: string | null; displayName?: string | null },
): Promise<User> {
  if (!user.isGuest) throw conflict('Account is already registered');
  return getRepositories().users.update(user.id, {
    username: input.username,
    email: input.email ?? null,
    passwordHash: await hashPassword(input.password),
    displayName: input.displayName?.trim() || input.username,
    isGuest: false,
  });
}

export async function changePassword(
  user: User,
  currentPassword: string,
  newPassword: string,
): Promise<void> {
  const repos = getRepositories();
  if (!user.passwordHash) throw forbidden('Guest accounts do not have a password');
  if (!(await verifyPassword(currentPassword, user.passwordHash))) {
    throw invalidCredentials('Current password is incorrect');
  }
  await repos.users.update(user.id, { passwordHash: await hashPassword(newPassword) });
  await repos.tokens.revokeAllForUser(user.id);
}

export async function updateProfile(
  user: User,
  patch: { displayName?: string; country?: string | null; avatarSkin?: BirdSkin },
): Promise<User> {
  if (patch.avatarSkin && !BIRD_SKINS.includes(patch.avatarSkin)) {
    throw conflict('Unknown bird skin', { field: 'avatarSkin', allowed: BIRD_SKINS });
  }
  return getRepositories().users.update(user.id, patch);
}

export interface ProfileResponse {
  user: PublicUser;
  stats: UserStats;
  achievements: { unlocked: number; total: number; points: number };
  best: { score: number; mode: string | null; achievedAt: string | null };
  rank: number | null;
}

export async function publicProfile(username: string): Promise<ProfileResponse> {
  const repos = getRepositories();
  const user = await repos.users.findByUsername(username);
  if (!user || user.isBanned) throw notFound('Player not found');

  const [stats, achievements, catalog, best, ranking] = await Promise.all([
    repos.stats.get(user.id),
    repos.achievements.forUser(user.id),
    repos.achievements.catalog(),
    repos.scores.bestForUser(user.id, null),
    repos.scores.rankForUser(user.id, { mode: null, window: 'all' }),
  ]);

  const unlockedCodes = new Set(achievements.filter((a) => a.unlockedAt).map((a) => a.code));
  const points = catalog
    .filter((definition) => unlockedCodes.has(definition.code))
    .reduce((sum, definition) => sum + definition.points, 0);

  return {
    user: toPublicUser(user),
    stats: stats ?? {
      userId: user.id,
      bestScore: 0,
      bestScoreMode: null,
      totalScore: 0,
      gamesPlayed: 0,
      totalCoins: 0,
      totalPipes: 0,
      totalDurationMs: 0,
      longestRunMs: 0,
      bestCombo: 0,
      updatedAt: user.createdAt,
    },
    achievements: { unlocked: unlockedCodes.size, total: catalog.length, points },
    best: {
      score: best?.score ?? 0,
      mode: best?.mode ?? null,
      achievedAt: best?.submittedAt ?? null,
    },
    rank: ranking?.entry.rank ?? null,
  };
}

export const asPrivate = (user: User): PrivateUser => toPrivateUser(user);
export const asPublic = (user: User): PublicUser => toPublicUser(user);
