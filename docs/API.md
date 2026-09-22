# API reference

Base URL: `http://localhost:4000` · all endpoints are under `/v1` except the
operational ones.

Interactive versions of this page ship with the server:

| | |
|---|---|
| **Swagger UI** | <http://localhost:4000/docs> — bundled locally, works offline |
| **ReDoc** | <http://localhost:4000/redoc> |
| **Spec** | [`backend/openapi/openapi.yaml`](../backend/openapi/openapi.yaml) · [`/openapi.json`](http://localhost:4000/openapi.json) |

The spec is the source of truth. A test asserts that every route the app serves
is documented and that every documented route exists, so the two cannot drift.

## Conventions

### Authentication

```http
Authorization: Bearer <accessToken>
```

Two token types:

| Token | Lifetime | Stored | Purpose |
|-------|----------|--------|---------|
| Access | 15 min | memory / Keychain | Every authenticated request |
| Refresh | 30 days | Keychain | Exchanged for a new pair |

Refresh tokens **rotate**: each successful refresh revokes the token it
consumed, and only SHA-256 hashes are stored server-side.

### Errors

One envelope, always:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Invalid request body",
    "details": { "source": "body", "issues": [{ "path": "score", "message": "Expected number" }] },
    "requestId": "9b1c…"
  }
}
```

`code` is stable and safe to branch on; `requestId` matches the `X-Request-Id`
response header and appears in the server logs.

| Code | Status |
|------|-------:|
| `bad_request` | 400 |
| `unauthorized`, `invalid_credentials`, `token_expired` | 401 |
| `forbidden` | 403 |
| `not_found` | 404 |
| `conflict` | 409 |
| `payload_too_large` | 413 |
| `validation_failed`, `unprocessable` | 422 |
| `rate_limited` | 429 |
| `internal_error` | 500 |
| `service_unavailable` | 503 |

### Rate limits

Reported through the standard `RateLimit-*` headers.

| Bucket | Endpoints | Default |
|--------|-----------|--------:|
| global | everything under `/v1` | 240/min |
| auth | register, login, guest, password | 20/min |
| submit | `POST /v1/scores` | 60/min |

## Discovery

### `GET /v1/meta/config`

The handshake. The game requires `protocol == "flappy-bird/1"` before enabling
anything online.

```bash
curl -s localhost:4000/v1/meta/config
```

```json
{
  "service": "flappy-bird-backend",
  "apiVersion": "1.0.0",
  "protocol": "flappy-bird/1",
  "environment": "development",
  "capabilities": ["auth.password", "auth.guest", "scores.submit", "leaderboard.global", "…"],
  "limits": { "maxScore": 100000, "leaderboardPageMax": 100, "rateLimitPerWindow": 240, "rateLimitWindowMs": 60000 },
  "gameModes": ["classic", "endless", "timeAttack", "hardcore", "zen", "daily"],
  "birdSkins": ["classic", "midnight", "ember", "mint", "royal", "glitch", "aurora", "phoenix"],
  "requiresSignedRuns": false,
  "docs": "http://localhost:4000/docs"
}
```

### `GET /v1/meta/stats`

Aggregate, non-identifying counters — safe to render on a marketing page.

## Auth

| Method | Path | Auth | Purpose |
|--------|------|:----:|---------|
| `POST` | `/v1/auth/register` | — | Create a password account |
| `POST` | `/v1/auth/login` | — | Sign in |
| `POST` | `/v1/auth/guest` | — | Create or resume a device-bound guest |
| `POST` | `/v1/auth/refresh` | — | Rotate tokens |
| `POST` | `/v1/auth/logout` | — | Revoke one refresh token |
| `POST` | `/v1/auth/logout-all` | ✅ | Revoke every session |
| `GET` | `/v1/auth/me` | ✅ | Current account, stats, session count |
| `PATCH` | `/v1/auth/password` | ✅ | Change password (revokes all sessions) |
| `POST` | `/v1/auth/upgrade` | ✅ | Promote a guest, keeping all history |
| `DELETE` | `/v1/auth/account` | ✅ | Delete everything |

```bash
# Register
curl -X POST localhost:4000/v1/auth/register \
  -H 'content-type: application/json' \
  -d '{"username":"skyhopper","password":"correct-horse-battery","country":"US"}'
```

```json
{
  "user": { "id": "…", "username": "skyhopper", "displayName": "skyhopper", "isGuest": false },
  "tokens": { "accessToken": "eyJ…", "refreshToken": "…", "tokenType": "Bearer", "expiresIn": 900 }
}
```

```bash
# Guest — 201 the first time, 200 when resuming the same device
curl -X POST localhost:4000/v1/auth/guest \
  -H 'content-type: application/json' \
  -d '{"deviceId":"6E2A9C71-4F0B-4D2A-9C1E-8F0C2B7A5D31"}'
```

## Scores

### `POST /v1/scores` 🔒

```bash
curl -X POST localhost:4000/v1/scores \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{
    "score": 42, "mode": "classic", "coins": 17, "pipesPassed": 42,
    "durationMs": 61500, "maxCombo": 9, "powerUpsUsed": 2, "seed": "a1b2c3d4",
    "clientVersion": "1.1.0", "deviceModel": "iPhone15,3"
  }'
```

```json
{
  "score": { "id": "…", "score": 42, "flagged": false, "submittedAt": "2026-03-19T09:14:02.881Z" },
  "stats": { "bestScore": 42, "gamesPlayed": 12, "totalCoins": 148 },
  "personalBest": true,
  "rank": 3,
  "totalPlayers": 128,
  "unlockedAchievements": [{ "code": "sky_rookie", "progress": 42, "unlockedAt": "…" }],
  "flagged": false,
  "flagReasons": []
}
```

An implausible run still returns `201`, with `flagged: true` and the reasons.
An *impossible* one returns `422`.

| Method | Path | Auth | Purpose |
|--------|------|:----:|---------|
| `GET` | `/v1/scores/me` | ✅ | History, newest first, `before` cursor |
| `GET` | `/v1/scores/me/best` | ✅ | Personal best, optionally per mode |
| `GET` | `/v1/scores/{id}` | ✅ | One run (owner or admin) |

## Leaderboards

| Method | Path | Auth | Purpose |
|--------|------|:----:|---------|
| `GET` | `/v1/leaderboard` | — | Global, paginated |
| `GET` | `/v1/leaderboard/me` | ✅ | Your rank plus neighbours |
| `GET` | `/v1/leaderboard/friends` | ✅ | You against the people you follow |
| `GET` | `/v1/leaderboard/stream` | — | Server-Sent Events |

```bash
curl -s "localhost:4000/v1/leaderboard?window=weekly&mode=classic&limit=10"
```

Query parameters: `mode`, `window` (`all` · `daily` · `weekly` · `monthly`),
`limit` (≤ 100), `offset`.

Ranking rules — identical in both storage drivers, and tested:

1. only unflagged runs from unbanned players are eligible;
2. a player appears **once**, represented by their best run in the window;
3. ties share a rank (1, 1, 3 …) and the earlier run is listed first.

Windows are evaluated in UTC; weeks start on Monday.

### Live updates

```bash
curl -N localhost:4000/v1/leaderboard/stream
```

```
event: connected
data: {"type":"connected","at":"2026-03-19T09:14:00.000Z"}

event: score.submitted
data: {"type":"score.submitted","at":"…","payload":{"username":"skyhopper","score":42,"mode":"classic","rank":3}}
```

A `heartbeat` arrives every 25 s.

## Achievements

| Method | Path | Auth | Purpose |
|--------|------|:----:|---------|
| `GET` | `/v1/achievements` | — | The catalog |
| `GET` | `/v1/achievements/me` | ✅ | The catalog annotated with your progress |
| `POST` | `/v1/achievements/me/sync` | ✅ | Merge offline unlocks |

```bash
curl -X POST localhost:4000/v1/achievements/me/sync \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"achievements":[{"code":"night_owl","progress":1,"unlockedAt":"2026-03-19T02:11:00.000Z"}]}'
```

The merge is monotonic: progress only increases and an unlock timestamp is never
overwritten, so replaying an old payload is a no-op.

## Daily challenge

| Method | Path | Auth | Purpose |
|--------|------|:----:|---------|
| `GET` | `/v1/challenges/today` | — | Today's parameters and rollover time |
| `GET` | `/v1/challenges/{date}` | — | Any date |
| `GET` | `/v1/challenges/{date}/leaderboard` | — | That day's board |
| `POST` | `/v1/challenges/today/entries` | ✅ | Submit a score (best per day wins) |

Parameters are derived from `SHA-256("flappy-bird-daily:YYYY-MM-DD")`, so the
game produces the identical challenge offline.

## Friends

| Method | Path | Auth | Purpose |
|--------|------|:----:|---------|
| `GET` | `/v1/friends` | ✅ | Who you follow |
| `PUT` | `/v1/friends/{username}` | ✅ | Follow (idempotent) |
| `DELETE` | `/v1/friends/{username}` | ✅ | Unfollow |

## Users

| Method | Path | Auth | Purpose |
|--------|------|:----:|---------|
| `GET` | `/v1/users/me` | ✅ | Own profile |
| `PATCH` | `/v1/users/me` | ✅ | Display name, country, skin |
| `GET` | `/v1/users/me/stats` | ✅ | Aggregates, best run, rank |
| `GET` | `/v1/users/search?q=` | — | Find players |
| `GET` | `/v1/users/{username}` | — | Public profile |
| `GET` | `/v1/users/{username}/scores` | — | Recent runs (flagged omitted) |

## Admin 🔐

Requires `role = 'admin'` or `X-Admin-Token`.

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/v1/admin/stats` | Instance counters |
| `POST` | `/v1/admin/users/{username}/ban` | Ban and revoke sessions |
| `DELETE` | `/v1/admin/users/{username}/ban` | Lift a ban |
| `POST` | `/v1/admin/scores/{id}/flag` | Hide a run, recompute stats |
| `DELETE` | `/v1/admin/scores/{id}` | Delete a run |
| `POST` | `/v1/admin/maintenance/purge-tokens` | Remove expired refresh tokens |
| `POST` | `/v1/admin/maintenance/recompute-stats/{username}` | Rebuild aggregates |

## Operations

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/healthz` | Health summary with the active driver |
| `GET` | `/livez` | Liveness — never touches the database |
| `GET` | `/readyz` | Readiness — pings storage |
| `GET` | `/metrics` | Prometheus exposition |
