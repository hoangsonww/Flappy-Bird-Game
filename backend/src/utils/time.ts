/** Time helpers shared by leaderboards, challenges and token expiry. */

export const MS_PER_SECOND = 1_000;
export const MS_PER_MINUTE = 60 * MS_PER_SECOND;
export const MS_PER_HOUR = 60 * MS_PER_MINUTE;
export const MS_PER_DAY = 24 * MS_PER_HOUR;

/** `YYYY-MM-DD` in UTC. Daily challenges and daily boards roll over at 00:00Z. */
export function utcDateKey(date: Date = new Date()): string {
  return date.toISOString().slice(0, 10);
}

/** Inclusive start of the UTC window for a leaderboard period. */
export function windowStart(
  window: 'all' | 'daily' | 'weekly' | 'monthly',
  now = new Date(),
): Date | null {
  switch (window) {
    case 'all':
      return null;
    case 'daily':
      return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    case 'weekly': {
      // ISO week: Monday is the first day.
      const day = now.getUTCDay();
      const daysSinceMonday = (day + 6) % 7;
      const monday = new Date(
        Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - daysSinceMonday),
      );
      return monday;
    }
    case 'monthly':
      return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    default:
      return null;
  }
}

/** Parse a compact duration string such as `15m`, `2h`, `30d`, `45s`, or raw seconds. */
export function parseDuration(value: string): number {
  const match = /^(\d+)\s*(ms|s|m|h|d)?$/i.exec(value.trim());
  if (!match) throw new Error(`Unsupported duration: ${value}`);
  const amount = Number(match[1]);
  switch ((match[2] ?? 's').toLowerCase()) {
    case 'ms':
      return amount;
    case 's':
      return amount * MS_PER_SECOND;
    case 'm':
      return amount * MS_PER_MINUTE;
    case 'h':
      return amount * MS_PER_HOUR;
    case 'd':
      return amount * MS_PER_DAY;
    default:
      return amount * MS_PER_SECOND;
  }
}

export const nowIso = (): string => new Date().toISOString();
