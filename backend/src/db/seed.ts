#!/usr/bin/env tsx
/**
 * Demo data seeder.
 *
 * Creates a handful of players with plausible run histories so the leaderboard,
 * profile and achievement screens have something to show on a fresh database.
 *
 *   npm run seed                 # 12 players, ~30 runs each
 *   SEED_PLAYERS=40 npm run seed
 *
 * Passwords for every seeded account: `flappybird`
 */
import { GAME_MODES, BIRD_SKINS, type GameMode } from '../config/constants.js';
import { logger } from '../config/logger.js';
import { deriveDailyChallenge } from '../domain/challenge.js';
import { evaluateStatAchievements } from '../domain/achievements.js';
import { closeRepositories, getRepositories } from '../repositories/index.js';
import { hashPassword } from '../utils/crypto.js';
import { utcDateKey } from '../utils/time.js';

const NAMES = [
  'skyhopper',
  'pipedodger',
  'featherfall',
  'nimbus',
  'tailwind',
  'zephyr',
  'cloudchaser',
  'gustavo',
  'aeronaut',
  'birdbrain',
  'flapjack',
  'updraft',
  'thermalrider',
  'wingman',
  'sparrowhawk',
  'kestrel',
  'peregrine',
  'albatross',
  'starling',
  'swiftly',
];

const COUNTRIES = ['US', 'VN', 'GB', 'DE', 'JP', 'BR', 'CA', 'AU', 'FR', 'KR', 'IN', 'SE'];

function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pick<T>(items: readonly T[]): T {
  return items[randomInt(0, items.length - 1)]!;
}

async function main(): Promise<void> {
  const repos = getRepositories();
  const playerCount = Math.min(Number(process.env.SEED_PLAYERS ?? 12), NAMES.length);
  const passwordHash = await hashPassword('flappybird');

  logger.info({ driver: repos.driver, playerCount }, 'Seeding demo data');

  const today = utcDateKey();
  const challenge =
    (await repos.challenges.getByDate(today)) ??
    (await repos.challenges.create(deriveDailyChallenge(today)));

  for (let index = 0; index < playerCount; index += 1) {
    const username = NAMES[index]!;
    const existing = await repos.users.findByUsername(username);
    if (existing) {
      logger.info({ username }, 'Player already exists, skipping');
      continue;
    }

    const user = await repos.users.create({
      username,
      email: `${username}@example.com`,
      passwordHash,
      displayName: username.charAt(0).toUpperCase() + username.slice(1),
      country: pick(COUNTRIES),
      avatarSkin: pick(BIRD_SKINS),
      isGuest: false,
      deviceId: null,
    });

    const skill = randomInt(3, 60);
    const runs = randomInt(12, 40);

    for (let run = 0; run < runs; run += 1) {
      const mode: GameMode = pick(GAME_MODES.filter((m) => m !== 'daily'));
      const score = Math.max(0, Math.round(skill + randomInt(-skill, skill) / 2));
      const pipes = score;
      const inserted = await repos.scores.insert({
        userId: user.id,
        score,
        mode,
        coins: randomInt(0, Math.max(1, score)),
        pipesPassed: pipes,
        durationMs: Math.max(1_000, pipes * randomInt(900, 1_400) + randomInt(500, 3_000)),
        maxCombo: randomInt(0, Math.max(1, Math.floor(score / 3))),
        powerUpsUsed: randomInt(0, 4),
        seed: Math.random().toString(16).slice(2, 10),
        clientVersion: '1.1.0',
        deviceModel: 'Seed/Simulator',
      });
      await repos.stats.applyScore(inserted);
    }

    const stats = await repos.stats.get(user.id);
    if (stats) {
      await repos.achievements.upsertMany(
        evaluateStatAchievements(stats, await repos.achievements.forUser(user.id)),
      );
      await repos.challenges.upsertEntry({
        date: challenge.date,
        userId: user.id,
        score: Math.round(stats.bestScore * 0.8),
        submittedAt: new Date().toISOString(),
      });
    }

    logger.info({ username, runs }, 'Seeded player');
  }

  // Make a small friend graph so /v1/leaderboard/friends has data.
  const first = await repos.users.findByUsername(NAMES[0]!);
  if (first) {
    for (let index = 1; index < Math.min(6, playerCount); index += 1) {
      const friend = await repos.users.findByUsername(NAMES[index]!);
      if (friend) await repos.friends.add(first.id, friend.id);
    }
  }

  const totals = await repos.stats.globalTotals();
  logger.info(totals, 'Seed complete');
  console.log(
    `\nSeeded ${totals.players} players / ${totals.games} runs.\n` +
      `Log in with any of: ${NAMES.slice(0, playerCount).join(', ')}\nPassword: flappybird\n`,
  );
}

main()
  .then(async () => {
    await closeRepositories();
    process.exit(0);
  })
  .catch(async (error) => {
    console.error(`✖ Seeding failed: ${(error as Error).message}`);
    await closeRepositories();
    process.exit(1);
  });
