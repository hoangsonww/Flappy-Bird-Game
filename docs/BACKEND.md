# Backend

Optional companion service for accounts, leaderboards, achievements and the
daily challenge. **The game never needs it.**

- Node.js 20+ · TypeScript · Express 5 · Zod · PostgreSQL 16
- 106 tests, run against **both** storage drivers in CI
- OpenAPI 3.1 with Swagger UI bundled locally (works offline)

## Run it

### With Docker — one command

```bash
make up
```

Postgres, migrations and the API. Ready at <http://localhost:4000>, docs at
<http://localhost:4000/docs>.

### Without Docker — zero infrastructure

```bash
cd backend
npm install
npm run dev
```

Defaults to `DB_DRIVER=memory`: the API is fully functional and data lives for
the lifetime of the process. Perfect for a first look or for working on the
game's networking.

### With your own Postgres

```bash
cd backend
cp .env.example .env          # set DB_DRIVER=postgres and DATABASE_URL
npm run migrate
npm run dev
```

## Verify it

```bash
make health     # the health document
make smoke      # walks the same path the game does, end to end
make seed       # 12 demo players with plausible run histories
```

`make smoke` is the fastest way to know the whole thing works:

```
✓ health check responds
✓ discovery handshake advertises flappy-bird/1
✓ guest account created
✓ run accepted and not flagged
✓ leaderboard lists the run
✓ achievement sync merged
✓ impossible run rejected with 422
```

## Documentation endpoints

| URL | What it is |
|-----|------------|
| `/docs` | Swagger UI. Assets are bundled — no internet needed. |
| `/redoc` | ReDoc reference (loads ReDoc from a CDN). |
| `/openapi.json` | The specification as JSON. |
| `/openapi.yaml` | The specification as YAML — the source of truth. |
| `/healthz` | Health summary, including the active storage driver. |
| `/livez` · `/readyz` | Liveness and readiness probes. |
| `/metrics` | Prometheus exposition. |

Set `ENABLE_DOCS=false` to turn the first four off.

<p align="center">
  <img src="../img/screens/leaderboard.png" alt="The in-game leaderboard" width="260" />
</p>

## How the game finds it

```mermaid
sequenceDiagram
    autonumber
    participant G as iOS game
    participant S as Backend

    Note over G: On launch, in the background
    G->>S: GET /v1/meta/config
    alt protocol == "flappy-bird/1"
        S-->>G: 200 capabilities, limits, modes
        G->>S: POST /v1/auth/guest { deviceId }
        S-->>G: 201 user + tokens
        G->>S: POST /v1/scores (queued runs first)
        S-->>G: 201 rank, stats, unlocked achievements
    else anything else
        S--xG: timeout / wrong protocol
        Note over G: Stays offline. Runs queue locally.
    end
```

Candidates, in order:

1. the URL typed into **Settings ▸ Server**
2. `FlappyBackendURL` in `Info.plist` — how a fork ships a default server
3. `http://localhost:4000`
4. `http://127.0.0.1:4000`

Each is probed with a 1.8 s timeout. A server is accepted only if it answers
with `protocol: "flappy-bird/1"`.

> **Running on a real device?** `localhost` is the phone, not your Mac. Put your
> Mac's LAN address into Settings ▸ Server ▸ Server URL, e.g.
> `http://192.168.1.20:4000`, and make sure both are on the same network.

## Configuration

Every setting has a default, so an empty `.env` works in development. The full
list lives in [`backend/.env.example`](../backend/.env.example).

### Runtime

| Variable | Default | Notes |
|----------|---------|-------|
| `NODE_ENV` | `development` | `production` enables strict checks. |
| `PORT` / `HOST` | `4000` / `0.0.0.0` | |
| `PUBLIC_URL` | `http://localhost:$PORT` | Used in docs links and the banner. |
| `LOG_LEVEL` | `info` | pino levels. |
| `TRUST_PROXY` | `false` | Only enable behind a proxy you control. |

### Storage

| Variable | Default | Notes |
|----------|---------|-------|
| `DB_DRIVER` | `memory` | `postgres` for durability. Rejected in production. |
| `DATABASE_URL` | `postgres://flappy:flappy@localhost:5432/flappybird` | |
| `DATABASE_SSL` | `false` | |
| `DATABASE_POOL_MAX` | `10` | |
| `DATABASE_AUTO_MIGRATE` | `true` | Applies pending migrations at boot. |

### Authentication

| Variable | Default | Notes |
|----------|---------|-------|
| `JWT_ACCESS_SECRET` | *(generated)* | **Required in production.** `openssl rand -hex 48` |
| `JWT_REFRESH_SECRET` | *(generated)* | **Required in production.** |
| `ACCESS_TOKEN_TTL` | `15m` | |
| `REFRESH_TOKEN_TTL_DAYS` | `30` | |
| `BCRYPT_ROUNDS` | `11` | |

In development, missing secrets are generated at boot and a warning is printed —
tokens then stop working after a restart, which is fine locally and fatal in
production, so production refuses to start without them.

### Limits and fair play

| Variable | Default | Notes |
|----------|---------|-------|
| `RATE_LIMIT_MAX` | `240`/min | The whole `/v1` surface. |
| `AUTH_RATE_LIMIT_MAX` | `20`/min | Credential endpoints. |
| `SUBMIT_RATE_LIMIT_MAX` | `60`/min | `POST /v1/scores`. |
| `MAX_SCORE` | `100000` | Hard rejection above this. |
| `MAX_PIPES_PER_SECOND` | `1.6` | Drives the "too fast" heuristic. |
| `RUN_SIGNING_SECRET` | *(empty)* | Enables HMAC run signatures. |
| `REQUIRE_SIGNED_RUNS` | `false` | Reject unsigned runs. |
| `ADMIN_TOKEN` | *(empty)* | Accepted as `X-Admin-Token` on `/v1/admin`. |

### Features

`ENABLE_DOCS`, `ENABLE_METRICS`, `ENABLE_SSE`, `ENABLE_GUEST_ACCOUNTS` — all
default to `true`.

## Fair play

Submitted runs are checked for plausibility. The rule is: never reject something
a real player could have done.

| Signal | Outcome |
|--------|---------|
| Score above `MAX_SCORE` | **422 rejected** |
| Score greater than pipes passed (except Time Attack) | **422 rejected** |
| A scoring run with zero duration | **422 rejected** |
| Missing/invalid signature when `REQUIRE_SIGNED_RUNS` | **422 rejected** |
| Faster than `MAX_PIPES_PER_SECOND` | flagged |
| Coins wildly out of proportion to pipes | flagged |
| Combo greater than score | flagged |
| More power-ups than could have spawned | flagged |
| Time Attack run longer than the mode allows | flagged |
| More than 20 submissions in a minute | flagged |

A **flagged** run is stored with its reasons, returned to the player as
`flagged: true`, and then excluded from every leaderboard and from aggregate
stats. Nothing is silently dropped, so a moderator can review it later.

## Operations

```bash
make logs              # tail the API
make ps                # container status
make psql              # a shell on the database
make migrate-status    # which migrations have run
make up-tools          # + pgweb at :8081
make up-observability  # + Prometheus :9090 and Grafana :3001
```

Custom metrics, alongside the Node.js defaults:

| Metric | Type | Labels |
|--------|------|--------|
| `http_requests_total` | counter | method, route, status |
| `http_request_duration_seconds` | histogram | method, route, status |
| `flappy_scores_submitted_total` | counter | mode, flagged |
| `flappy_accounts_created_total` | counter | kind |

## Moderation

`/v1/admin` accepts either an account with `role = 'admin'` or a request
carrying `X-Admin-Token: $ADMIN_TOKEN`.

```bash
export ADMIN=your-admin-token

curl -X POST localhost:4000/v1/admin/users/cheater/ban \
  -H "X-Admin-Token: $ADMIN" -H 'content-type: application/json' \
  -d '{"reason":"macro use"}'

curl -X POST localhost:4000/v1/admin/scores/<id>/flag \
  -H "X-Admin-Token: $ADMIN" -H 'content-type: application/json' \
  -d '{"reason":"impossible trajectory"}'
```

Banning revokes every session, hides the player from all boards, and blocks
sign-in. Flagging a run recomputes the owner's aggregates.

## Project structure

```
backend/
├── src/
│   ├── app.ts              Express wiring, no side effects (tests import it)
│   ├── server.ts           boot, migrations, banner, graceful shutdown
│   ├── config/             env (zod), logger, constants shared with the game
│   ├── routes/             one file per resource
│   ├── services/           tokens, scores, anti-cheat, SSE hub
│   ├── repositories/       contracts + postgres + memory
│   ├── domain/             models, achievement catalog, challenge derivation
│   ├── middleware/         auth, validate, rate limit, metrics, errors
│   └── utils/              errors, crypto, time, pagination, ids
├── migrations/             forward-only SQL with checksums
├── openapi/openapi.yaml    the contract (46 paths, 49 operations)
├── scripts/                spec validation, smoke test
└── tests/                  106 tests
```

## Next

- [API reference](API.md) — every endpoint with examples
- [Database](DATABASE.md) — schema, indexes, the ranking query
- [Security model](SECURITY-MODEL.md) — tokens, hashing, threat model
