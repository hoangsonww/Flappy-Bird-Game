# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases are cut automatically from [Conventional Commits](https://www.conventionalcommits.org/)
on every merge to `master` — see [docs/CI-CD.md](docs/CI-CD.md).

## [Unreleased]

### ✨ Features

**Game**

- Six game modes: Classic, Endless, Time Attack, Hardcore, Zen and a daily challenge.
- Five power-ups — shield, slow-motion, coin magnet, double points and shrink — with
  stacking durations and HUD badges.
- Coins and a coin-streak combo multiplier (up to ×8) that feeds the shop.
- Eight unlockable bird skins.
- A bounded difficulty curve: gaps narrow, spawns quicken and the world speeds up
  over the first 40 pipes, then plateaus. Drifting pipe pairs appear past 25.
- Weather — wind, rain and fog — rolled deterministically from the run seed.
- A day/night cycle that re-tints the world every 20 pipes.
- 17 achievements (910 points) with a toast queue, and bronze/silver/gold/platinum medals.
- A deterministic daily challenge derived from the date, identical on the server
  and offline.
- New screens: main menu with mode selection, leaderboard, achievements, shop,
  lifetime stats and settings, with a drag-to-scroll list container.
- Procedurally synthesised chiptune sound effects — no audio assets required.
- Haptics, pause, share, and accessibility options (reduce flashing, high contrast,
  and support for the system Reduce Motion setting).

**Backend (optional)**

- A complete Node.js + TypeScript + Express 5 API: accounts, guest sessions,
  score submission, leaderboards, achievements, friends and the daily challenge.
- JWT access tokens with rotating, hashed refresh tokens; bcrypt password hashing.
- Global, daily, weekly and monthly leaderboards with tie-sharing ranks, plus a
  friends-only board and a Server-Sent Events stream.
- Server-side fair play: impossible runs rejected, improbable runs flagged and
  excluded from boards, with optional HMAC run signatures.
- Two storage drivers — PostgreSQL and in-memory — behind one set of repository
  contracts, with the whole test suite running against both.
- OpenAPI 3.1 specification (46 paths, 49 operations) served through bundled
  Swagger UI and ReDoc, guarded by a test that diffs it against the real routes.
- Prometheus metrics, health/liveness/readiness probes, structured logging with
  redaction, three rate-limit buckets and an admin moderation surface.

**Developer experience**

- A `Makefile` with 35+ documented targets covering the game, the backend, Docker
  and the quality gates.
- Docker Compose with `tools` and `observability` profiles (pgweb, Prometheus,
  provisioned Grafana), a multi-stage non-root image and healthchecks.
- A dev container for backend work.
- `scripts/generate_xcodeproj.py`, which generates the Xcode project from the file
  tree with deterministic IDs and a `--check` mode used by CI.
- `scripts/capture-media.sh`, which drives the simulator to produce every
  screenshot and the demo GIF reproducibly.
- `make doctor`, `make bootstrap`, and a smoke test that walks the same path the
  game does.
- CI across backend quality, a 2×2 test matrix, an end-to-end Compose smoke test,
  a container build, the iOS build and 122 Swift tests, CodeQL and Dependabot.
- Automatic releases derived from Conventional Commits, publishing a changelog,
  a GitHub release and a multi-architecture image to GHCR.

### 🐛 Fixes

- Pipes now reach the top and bottom of the screen. The fixed-height artwork left
  open sky above the top pipe on modern displays, which made the obstacle
  avoidable; the sprites are nine-sliced so only the shaft stretches.
- The bird's mass is pinned, so shrinking its hitbox for fairness no longer makes
  every flap launch it much higher.
- Wind can no longer push the bird off-screen — lateral drift is bounded and
  springs back.
- A session now survives a Keychain write failure, which previously left the app
  looking connected while silently never uploading anything.
- Run history is deterministically ordered; two runs saved in the same
  millisecond used to come back in an arbitrary order.
- Leaderboard ties share a rank in both storage drivers. They previously did not
  in SQL.
- `user_stats` no longer reuses one query parameter for an `INTEGER` and a
  `BIGINT` column, which Postgres refuses to type-infer.
- Long list rows are truncated instead of running underneath the value column.
- The app icon set is complete, including the iPad 83.5 pt slot.
- The game no longer loads `GameScene.sks` through `NSKeyedUnarchiver`; scenes are
  built in code and sized to the view, so the game works on every device and
  orientation.

### 📚 Documentation

- A rewritten README with real screenshots and a recorded demo.
- 14 guides under `docs/`, with Mermaid diagrams throughout.
- Three architecture decision records.
- A marketing landing page (`index.html`) with a playable in-browser demo.

## [1.2.0] - 2024

Earlier releases predate this changelog. See the
[commit history](https://github.com/hoangsonww/Flappy-Bird-Game/commits/master).
