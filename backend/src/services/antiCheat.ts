/**
 * Server-side plausibility checks for submitted runs.
 *
 * Philosophy: never reject a run a legitimate player could have produced. Runs
 * that are *impossible* are rejected; runs that are merely *improbable* are
 * stored but flagged, which keeps them out of leaderboards while preserving the
 * evidence for review via `GET /v1/admin/flagged`.
 */
import { env } from '../config/env.js';
import type { GameMode } from '../config/constants.js';
import { signRun, safeEqual } from '../utils/crypto.js';
import { unprocessable } from '../utils/errors.js';

export interface RunSubmission {
  mode: GameMode;
  score: number;
  coins: number;
  pipesPassed: number;
  durationMs: number;
  maxCombo: number;
  powerUpsUsed: number;
  seed: string;
  signature?: string | null;
}

export interface Verdict {
  /** `accept` stores a clean run, `flag` stores a hidden run, `reject` throws. */
  outcome: 'accept' | 'flag';
  reasons: string[];
}

/** Minimum time a single pipe can take, derived from MAX_PIPES_PER_SECOND. */
const minMsPerPipe = () => 1_000 / env.MAX_PIPES_PER_SECOND;

export function verifyRun(submission: RunSubmission): Verdict {
  const reasons: string[] = [];

  // ── Hard rejections: physically impossible payloads ────────────────────────
  if (submission.score > env.MAX_SCORE) {
    throw unprocessable(`Score exceeds the maximum accepted value (${env.MAX_SCORE})`, {
      field: 'score',
    });
  }
  if (submission.pipesPassed < submission.score && submission.mode !== 'timeAttack') {
    throw unprocessable('Score cannot exceed the number of pipes passed', { field: 'score' });
  }
  if (submission.durationMs === 0 && submission.score > 0) {
    throw unprocessable('A scoring run must have a non-zero duration', { field: 'durationMs' });
  }
  if (env.REQUIRE_SIGNED_RUNS) {
    const expected = signRun(submission);
    if (!submission.signature || !safeEqual(expected, submission.signature)) {
      throw unprocessable('Run signature is missing or invalid', { field: 'signature' });
    }
  }

  // ── Soft signals: store, but keep off the board ────────────────────────────
  const requiredMs = submission.pipesPassed * minMsPerPipe();
  if (submission.pipesPassed > 3 && submission.durationMs < requiredMs) {
    reasons.push(
      `run too short for ${submission.pipesPassed} pipes ` +
        `(${submission.durationMs}ms < ${Math.round(requiredMs)}ms)`,
    );
  }
  if (submission.coins > submission.pipesPassed * 3 + 5) {
    reasons.push('coin count is disproportionate to pipes passed');
  }
  if (submission.maxCombo > submission.score) {
    reasons.push('combo exceeds score');
  }
  if (submission.powerUpsUsed > Math.ceil(submission.durationMs / 5_000) + 3) {
    reasons.push('more power-ups than could have spawned');
  }
  if (submission.mode === 'timeAttack' && submission.durationMs > 90_000) {
    reasons.push('time attack run longer than the mode allows');
  }
  if (submission.signature && env.RUN_SIGNING_SECRET) {
    const expected = signRun(submission);
    if (!safeEqual(expected, submission.signature)) reasons.push('run signature mismatch');
  }

  return { outcome: reasons.length > 0 ? 'flag' : 'accept', reasons };
}

/** Rate-based heuristic: too many submissions in a short window. */
export function verifySubmissionRate(runsInLastMinute: number): string | null {
  return runsInLastMinute > 20 ? 'submission rate above human limits' : null;
}
