# Contributing

Thanks for being here. This is a small project, so the process is short.

## Before you start

```bash
git clone https://github.com/hoangsonww/Flappy-Bird-Game.git
cd Flappy-Bird-Game
make doctor      # what do you have, what does it unlock
make bootstrap   # git hooks, backend dependencies, .env
```

Only **Xcode** and **Python 3** are required. Node and Docker are needed solely
for the optional backend.

Full setup notes: [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md).

## The one rule

**The game must keep working with no backend at all.** Every online feature needs
an offline path — the leaderboard screen falls back to local scores, the daily
challenge is derived locally, runs queue and upload later. A change that makes
the server necessary will be asked to change.

## Workflow

1. Open an issue first for anything substantial. Small fixes can go straight to a PR.
2. Branch from `master`: `feat/coin-magnet`, `fix/leaderboard-ties`.
3. Commit with [Conventional Commits](https://www.conventionalcommits.org/) —
   the release version is derived from them.
4. Run the checks.
5. Open a PR using the template.

### Commit prefixes

| Prefix | Release | Use for |
|--------|---------|---------|
| `feat` | minor | New behaviour |
| `fix` | patch | Bug fixes |
| `perf` | patch | Faster, same behaviour |
| `refactor` | none | No behaviour change |
| `docs` | none | Documentation only |
| `test` | none | Tests only |
| `build`, `ci`, `chore` | none | Tooling |

Add `!` or a `BREAKING CHANGE:` body for a major bump.

```
feat(game): add a coin magnet power-up
fix(backend): stop flagged runs from affecting aggregate stats
docs(api): document the SSE leaderboard stream
```

## Checks

```bash
make check    # xcodegen check, backend lint + types, OpenAPI, backend tests
make test     # Swift tests
```

Then launch the game once with the backend stopped.

## Adding a Swift file

Never edit `project.pbxproj` by hand — it is generated:

```bash
touch FlappyBird/Systems/MyNewSystem.swift
make xcodegen
```

CI fails if the checked-in project does not match the files on disk, and the
pre-commit hook from `make bootstrap` catches it before you push.

## Changing the API

1. Update the route and its tests.
2. Update [`backend/openapi/openapi.yaml`](../backend/openapi/openapi.yaml).
3. `make openapi` to validate it.
4. `make api-test` — a test diffs the specification against the real routes in
   both directions, so an undocumented endpoint fails the build.

If the change affects the game, update the Swift client in `FlappyBird/Backend/`
and its tests too.

## Changing the database

Add a **new** migration; never edit an applied one — the migrator reports that as
drift rather than silently diverging.

```bash
# backend/migrations/005_your_change.sql
make migrate
make api-test-pg     # run the suite against Postgres
```

If you change the repository contracts, both drivers must implement them. The
shared suite runs against both, which is how divergences get caught.

## Style

**Swift** — 4-space indent, 120 columns, `final class` unless subclassed.
`make format-swift` and `make lint-swift` if you have the tools installed.

**TypeScript** — 2-space indent, 100 columns, single quotes, trailing commas,
`strict`. `npm run format` in `backend/`.

**Comments** explain *why*. The code already says what it does.

## Screenshots

Gameplay changes deserve a picture. `make media` regenerates every screenshot
from the simulator — reproducible, because the app can open any screen
directly.

## What gets merged quickly

- A fix with a test that fails without it
- Documentation that corrects something wrong
- A feature discussed in an issue first
- Anything that makes the first-run experience simpler

## What gets pushed back on

- Making the backend mandatory
- New runtime dependencies without a clear reason
- Hand-edited `project.pbxproj`
- API changes without spec updates
- Large refactors bundled with behaviour changes

## Reporting bugs and vulnerabilities

Use the [issue templates](https://github.com/hoangsonww/Flappy-Bird-Game/issues/new/choose).
For security, follow [SECURITY.md](SECURITY.md) — please do not open a public issue.

## Licence

Contributions are accepted under the [MIT licence](../LICENSE).
