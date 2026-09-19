# Flappy Bird — backend

Optional companion API for the [Flappy Bird iOS game](../README.md): accounts,
leaderboards, achievements, friends and the daily challenge.

**The game does not need this.** It is fully playable offline; this service adds
the social layer, and the game detects it automatically when it is running.

```bash
npm install
npm run dev          # http://localhost:4000 — no database required
```

`DB_DRIVER` defaults to `memory`, so that really is the whole setup. For
durability, `make up` from the repository root starts Postgres and the API in
Docker with migrations applied.

## Documentation

|                        |                                                               |
| ---------------------- | ------------------------------------------------------------- |
| **Swagger UI**         | <http://localhost:4000/docs> — bundled locally, works offline |
| **ReDoc**              | <http://localhost:4000/redoc>                                 |
| **Specification**      | [`openapi/openapi.yaml`](openapi/openapi.yaml)                |
| **Guide**              | [`docs/BACKEND.md`](../docs/BACKEND.md)                       |
| **Endpoint reference** | [`docs/API.md`](../docs/API.md)                               |
| **Schema**             | [`docs/DATABASE.md`](../docs/DATABASE.md)                     |

## Scripts

| Command                              | What it does                                 |
| ------------------------------------ | -------------------------------------------- |
| `npm run dev`                        | Hot reload via tsx                           |
| `npm run build` / `start`            | Compile to `dist/` and run it                |
| `npm test`                           | 106 tests                                    |
| `npm run test:coverage`              | With a coverage report                       |
| `npm run lint` / `typecheck`         | ESLint and `tsc --noEmit`                    |
| `npm run migrate` / `migrate:status` | Apply / inspect migrations                   |
| `npm run seed`                       | 12 demo players with plausible run histories |
| `npm run openapi:validate`           | Structural validation of the specification   |
| `npm run smoke`                      | End-to-end check against a running server    |

Run the suite against Postgres too — this is what keeps the two storage drivers
honest, and it has already caught real divergences:

```bash
DB_DRIVER=postgres npm test
```

## Layout

```
src/
├── app.ts              Express wiring, free of side effects so tests can import it
├── server.ts           boot, migrations, banner, graceful shutdown
├── config/             env (zod-validated), logger, constants shared with the game
├── routes/             one file per resource — validate, delegate, respond
├── services/           tokens, score pipeline, anti-cheat, SSE hub
├── repositories/       storage contracts + postgres + memory implementations
├── domain/             models, the achievement catalog, challenge derivation
├── middleware/         auth, validation, rate limits, metrics, error envelope
└── utils/              errors, crypto, time, pagination, ids
```

## Configuration

Copy `.env.example` to `.env`. Every value has a default; the ones that matter:

| Variable             | Default                                              | Notes                                             |
| -------------------- | ---------------------------------------------------- | ------------------------------------------------- |
| `DB_DRIVER`          | `memory`                                             | `postgres` for durability. Refused in production. |
| `DATABASE_URL`       | `postgres://flappy:flappy@localhost:5432/flappybird` |                                                   |
| `JWT_ACCESS_SECRET`  | _generated_                                          | **Required in production.**                       |
| `JWT_REFRESH_SECRET` | _generated_                                          | **Required in production.**                       |
| `ADMIN_TOKEN`        | _empty_                                              | Accepted as `X-Admin-Token` on `/v1/admin`.       |
| `RUN_SIGNING_SECRET` | _empty_                                              | Enables HMAC run signatures.                      |

The full list is documented inline in [`.env.example`](.env.example).
