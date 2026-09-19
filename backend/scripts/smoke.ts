#!/usr/bin/env tsx
/**
 * End-to-end smoke test against a *running* server.
 *
 * Walks the same path the iOS game does: discovery → guest login → submit a run
 * → read the leaderboard → sync an achievement → check the daily challenge.
 *
 *   npm run smoke                       # http://localhost:4000
 *   BASE_URL=http://localhost:4000 npm run smoke
 */
const baseUrl = (process.env.BASE_URL ?? 'http://localhost:4000').replace(/\/$/, '');

let passed = 0;
let failed = 0;

function report(name: string, ok: boolean, detail = ''): void {
  if (ok) {
    passed += 1;
    console.log(`  ✓ ${name}`);
  } else {
    failed += 1;
    console.log(`  ✖ ${name}${detail ? ` — ${detail}` : ''}`);
  }
}

// Smoke output is untyped JSON by design; this script asserts on shape at runtime.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

async function json(path: string, init: RequestInit = {}): Promise<{ status: number; body: Json }> {
  const response = await fetch(`${baseUrl}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', ...(init.headers ?? {}) },
  });
  const text = await response.text();
  let body: unknown = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { status: response.status, body };
}

async function main(): Promise<void> {
  console.log(`\nSmoke testing ${baseUrl}\n`);

  const health = await json('/healthz');
  report('health check responds', health.status === 200, `status ${health.status}`);

  const config = await json('/v1/meta/config');
  report(
    'discovery handshake advertises flappy-bird/1',
    config.body?.protocol === 'flappy-bird/1',
    JSON.stringify(config.body?.protocol),
  );

  const deviceId = `smoke-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const guest = await json('/v1/auth/guest', {
    method: 'POST',
    body: JSON.stringify({ deviceId }),
  });
  report('guest account created', guest.status === 201, `status ${guest.status}`);

  const accessToken = guest.body?.tokens?.accessToken as string | undefined;
  const authHeaders = { authorization: `Bearer ${accessToken}` };
  report('guest received an access token', Boolean(accessToken));

  const run = await json('/v1/scores', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      score: 23,
      mode: 'classic',
      coins: 7,
      pipesPassed: 23,
      durationMs: 34_000,
      maxCombo: 5,
      powerUpsUsed: 1,
      seed: 'smoke',
      clientVersion: 'smoke-test',
    }),
  });
  report('run accepted and not flagged', run.status === 201 && run.body?.flagged === false);
  report('run returned a rank', typeof run.body?.rank === 'number');

  const board = await json('/v1/leaderboard?limit=5');
  report('leaderboard lists the run', board.status === 200 && board.body?.total >= 1);

  const mine = await json('/v1/leaderboard/me', { headers: authHeaders });
  report('own rank resolves', mine.status === 200 && mine.body?.rank !== null);

  const sync = await json('/v1/achievements/me/sync', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      achievements: [{ code: 'night_owl', progress: 1, unlockedAt: new Date().toISOString() }],
    }),
  });
  report('achievement sync merged', sync.status === 200 && sync.body?.synced === 1);

  const challenge = await json('/v1/challenges/today');
  report(
    'daily challenge available',
    challenge.status === 200 && Boolean(challenge.body?.challenge?.seed),
  );

  const cheat = await json('/v1/scores', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({ score: 500, mode: 'classic', pipesPassed: 10, durationMs: 1_000 }),
  });
  report('impossible run rejected with 422', cheat.status === 422);

  const docs = await fetch(`${baseUrl}/openapi.json`);
  report('openapi document served', docs.ok);

  console.log(`\n${failed === 0 ? '✓' : '✖'} ${passed} passed, ${failed} failed\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(`\n✖ Smoke test could not run: ${(error as Error).message}`);
  console.error(`  Is the server running at ${baseUrl}?\n`);
  process.exit(1);
});
