import { createHash } from 'node:crypto';
import type { GameMode } from '../config/constants.js';
import type { DailyChallenge } from './models.js';

const MODIFIERS = ['none', 'windy', 'foggy', 'nightfall', 'narrow', 'turbo'] as const;
const MODES: GameMode[] = ['classic', 'endless', 'timeAttack', 'hardcore'];

/**
 * Deterministically derive the daily challenge for a UTC date.
 *
 * Both the server and the game run this function, so a player can preview and
 * replay the exact same layout offline — the server is only needed to compare
 * scores with other players.
 *
 * The algorithm is intentionally simple and stable: SHA-256 of
 * `flappy-bird-daily:<YYYY-MM-DD>` seeds every derived parameter.
 */
export function deriveDailyChallenge(date: string): DailyChallenge {
  const digest = createHash('sha256').update(`flappy-bird-daily:${date}`).digest();
  const at = (index: number): number => digest[index % digest.length]!;

  const mode = MODES[at(0) % MODES.length]!;
  const modifier = MODIFIERS[at(1) % MODIFIERS.length]!;
  const pipeGap = 110 + (at(2) % 7) * 10; // 110 … 170
  const gravityScale = 0.85 + (at(3) % 7) * 0.05; // 0.85 … 1.15
  const speedScale = 0.9 + (at(4) % 9) * 0.05; // 0.90 … 1.30

  return {
    date,
    seed: digest.subarray(0, 8).toString('hex'),
    mode,
    pipeGap,
    gravityScale: Number(gravityScale.toFixed(2)),
    speedScale: Number(speedScale.toFixed(2)),
    modifier,
    description: describe(mode, modifier, pipeGap, speedScale),
    createdAt: new Date().toISOString(),
  };
}

function describe(mode: GameMode, modifier: string, pipeGap: number, speedScale: number): string {
  const parts = [`${mode} run`];
  if (pipeGap <= 125) parts.push('tight gaps');
  else if (pipeGap >= 160) parts.push('generous gaps');
  if (speedScale >= 1.2) parts.push('fast scroll');
  if (modifier !== 'none') parts.push(modifier);
  return `Today: ${parts.join(', ')}.`;
}
