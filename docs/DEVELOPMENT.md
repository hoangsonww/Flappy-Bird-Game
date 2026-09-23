# Development

## Requirements

| Tool | Needed for | Install |
|------|------------|---------|
| **Xcode 16+** | the game | App Store |
| **Python 3** | regenerating the Xcode project | ships with macOS |
| Node.js 20+ | the optional backend | `brew install node` |
| Docker | Postgres + API in one command | [docker.com](https://docs.docker.com/get-docker/) |
| SwiftLint / SwiftFormat | optional linting | `brew install swiftlint swiftformat` |

Check what you have:

```bash
make doctor
```

## Five minutes to playing

```bash
git clone https://github.com/hoangsonww/Flappy-Bird-Game.git
cd Flappy-Bird-Game
open "Flappy Bird.xcodeproj"   # then ⌘R
```

Or without touching Xcode's UI:

```bash
make run          # build, install and launch in a simulator
make demo         # the same, in self-playing attract mode
```

## Adding the backend

```bash
make up           # Postgres + API, migrations applied
make seed         # demo players so the leaderboard is not empty
make health
```

Relaunch the game and it will find the server on its own. Settings ▸ Server
shows the connection state.

## Everyday targets

```bash
make              # list every target with a description
make doctor       # toolchain check
make build        # build the game
make test         # Swift unit tests
make test-ui      # Swift UI tests (drives a simulator)
make run          # build + launch in the simulator
make xcodegen     # regenerate the Xcode project from the file tree
make check-links  # every doc link, image, anchor and sitemap entry
make check        # everything CI runs except the iOS build
make clean        # drop build output
```

Two details about those iOS targets are worth knowing, because both have bitten
this project already.

**They resolve a simulator UDID, never a name.** `scripts/simulator-udid.sh`
turns `SIMULATOR` (default `iPhone 17 Pro`) into a UDID, and falls back to any
available iPhone when that model is not installed. Passing `name=iPhone 17 Pro`
straight to `xcodebuild` looks equivalent but is not: with no `OS=` it defaults
to `OS:latest`, so the moment a newer runtime is installed a device that only
exists on the older one stops matching, and the failure reads
`Unable to find a device matching the provided destination specifier` — which
looks like a broken project rather than a missing runtime.

**They exit non-zero when something fails.** The recipes used to pipe
`xcodebuild` into `grep … || true`, which meant a compile error, a failing
assertion and a missing simulator all exited 0 and printed almost nothing.
`scripts/xcode.sh` filters the log the same way but keeps `xcodebuild`'s status
and prints the last 40 lines of the real output on failure, so a red run is red.

Backend:

```bash
make dev          # hot reload, in-memory storage, no infrastructure
make api-test     # 133 tests against the in-memory driver
make api-test-pg  # the same suite against Postgres
make api-lint     # eslint + tsc
make openapi      # validate the specification
make smoke        # end-to-end against a running server
make logs         # tail the API
```

## Adding a Swift file

**Never edit `project.pbxproj` by hand.** It is generated:

```bash
touch FlappyBird/Systems/MyNewSystem.swift
make xcodegen
```

Every `.swift` under `FlappyBird/` joins the app target and every one under
`FlappyBirdTests/` joins the unit-test target and every file under
`FlappyBirdUITests/` the UI-test target. Object IDs are derived from paths, so
the output is byte-for-byte stable and two branches adding files do not
conflict. CI runs `--check` and fails if the checked-in project is stale; the
pre-commit hook installed by `make bootstrap` catches it earlier.

## Launch switches

The app understands a few arguments, used by the capture tooling and handy when
working on one screen:

```bash
xcrun simctl launch booted com.hoangsonww.flappybird -screen shop -seed-demo
xcrun simctl launch booted com.hoangsonww.flappybird -demo -mode hardcore
xcrun simctl launch booted com.hoangsonww.flappybird -demo -debug-hud
```

| Flag | Effect |
|------|--------|
| `-screen <name>` | Open `menu`, `game`, `leaderboard`, `achievements`, `shop`, `stats` or `settings` directly |
| `-segment <n>` | Pre-select a filter chip on a list screen |
| `-mode <name>` | Force a game mode |
| `-seed-demo` | Fill the profile with plausible progress |
| `-demo` | Attract mode — the bird plays itself |
| `-demo-die <s>` | End an attract-mode run on cue, for capturing the summary |
| `-debug-hud` | Overlay live state, velocity and the targeted gap |

## Screenshots

```bash
make media
```

Boots a simulator, installs the app and captures every screen into
`img/screens/`. Because the app can open any screen directly, the output is
reproducible rather than a manual tapping session.

## Conventions

**Commits** follow [Conventional Commits](https://www.conventionalcommits.org/).
The release version is derived from them, so the prefix matters:

```
feat(game): add a coin magnet power-up
fix(backend): stop flagged runs from affecting aggregate stats
docs: expand the backend guide
```

| Prefix | Release |
|--------|---------|
| `feat` | minor |
| `fix`, `perf`, `revert` | patch |
| `type!` or `BREAKING CHANGE` | major |
| everything else | none |

**Swift** — 4-space indent, 120 columns, `final class` unless subclassed, types
in `UpperCamelCase`, everything else `lowerCamelCase`. Comments explain *why*.

**TypeScript** — 2-space indent, 100 columns, single quotes, trailing commas,
`strict` on. Routes stay thin: validate, delegate, respond.

## Before opening a pull request

```bash
make check        # xcodegen check, backend lint, OpenAPI, backend tests
make check-links  # docs, images, anchors, sitemap
make test         # Swift unit tests
make test-ui      # Swift UI tests
```

Then confirm the game still runs with **no backend at all** — that is the
project's core promise.

## Where things live

```
FlappyBird/          the game
FlappyBirdTests/     145 Swift unit tests
FlappyBirdUITests/   38 Swift UI tests
backend/             the optional API (133 tests × 2 storage drivers)
docs/                these guides
scripts/             project generation, xcodebuild wrappers, capture, release
robots.txt           crawler rules for the published page
sitemap.xml          the page and every screenshot, for search engines
site.webmanifest     name, colours and icons for a saved page
ops/                 Prometheus and Grafana configuration
.github/workflows/   CI, release, Pages
index.html           the landing page
```
