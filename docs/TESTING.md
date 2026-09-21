# Testing

289 tests: **147 Swift unit**, **34 Swift UI** and **108 backend**, the last
run against both storage drivers.

```bash
make test         # Swift unit tests (seconds)
make test-ui      # Swift UI tests — drives a simulator (minutes)
make test-all     # both Swift suites
make api-test     # backend, in-memory
make api-test-pg  # backend, Postgres
make check        # everything CI runs except the iOS build
make check-links  # docs, images, anchors, sitemap
```

Every one of those exits non-zero when it fails. That is worth stating because it
was not always true: the Swift targets used to pipe `xcodebuild` into
`grep … || true`, so a compile error, a failing assertion and a simulator that
did not exist all printed nothing and exited 0.
[`scripts/xcode.sh`](../scripts/xcode.sh) keeps `xcodebuild`'s status and dumps
the tail of the real log when it fails; the destination is a UDID resolved by
[`scripts/simulator-udid.sh`](../scripts/simulator-udid.sh) rather than a device
name, which would otherwise be matched against `OS:latest` only.

## Swift

`FlappyBirdTests/` — pure logic, no UI automation. Anything that touches
persistence gets its own `UserDefaults` suite so tests never see each other's
state or the simulator's real save file.

| File | Covers |
|------|--------|
| `CoreModelTests` | Medals, physics categories, run bookkeeping, mode rules |
| `SeededRandomTests` | Determinism, ranges, distribution of the seeded RNG |
| `DifficultyCurveTests` | Monotonicity, floors, per-mode behaviour, daily overrides |
| `PowerUpTests` | Activation, expiry, stacking, shield charges |
| `PersistenceTests` | Runs, wallet, skins, achievements, reset |
| `AchievementSystemTests` | Every unlock path, including the client-only ones |
| `DailyChallengeHelperTests` | **Byte-for-byte parity with the server** |
| `BackendClientTests` | URL normalisation, discovery order, DTO decoding |
| `AuthStoreTests` | Session storage when the Keychain is unavailable |
| `ThemeTests` | Skins, time-of-day cycle, weather weighting, font fallback |
| `GameOverPanelTests` | Summary-panel geometry for every row count |
| `ReplayTests` | Recording, interpolation, obstacle visibility, storage |

Two of these are contract tests rather than unit tests:

* **`DailyChallengeHelperTests`** pins four dates against values produced by the
  server's TypeScript. If either implementation drifts, players would silently
  get different challenges — so the test fails instead.
* **`AuthStoreTests`** exists because a silent Keychain failure once left the app
  looking connected while never uploading anything. The contract is now explicit:
  a stored session is always usable in-process.

```bash
xcodebuild -project "Flappy Bird.xcodeproj" -scheme FlappyBird \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FlappyBirdTests test
```

## Swift UI

`FlappyBirdUITests/` drives the real app on a simulator: it taps the actual
controls and asserts on what the screen publishes. The whole game is SpriteKit,
so there is no view hierarchy to query — every control is an `SKNode` that opts
into `UIAccessibility`, and the suite therefore doubles as an accessibility
test. If VoiceOver cannot reach a control, neither can the suite, and it fails.

| File | Covers |
|------|--------|
| `MenuUITests` | Every destination, mode cycling, and the mode card's layout at each mode |
| `GameplayUITests` | Starting a run, the pause overlay, the summary panel, Zen's no-death rule |
| `ListScreenUITests` | Every filter chip on the leaderboard, achievements and stats |
| `ShopUITests` | Buying, equipping, and what an unaffordable skin does |
| `SettingsUITests` | All three tabs, a toggle's value, the optional-backend copy |
| `ReplayUITests` | The replay list, playback, pause/restart, the advancing clock |

Every read of the accessibility tree goes through `waitForLabels`. A bare
`allElementsBoundByIndex` is a *snapshot*, and the window in which the tree is
still empty after a launch is long enough to lose on a loaded CI runner — that
single mistake was the whole of this suite's flakiness.

It found three real defects on its first run:

* every accessible node reported a **zero-size frame** — SpriteKit does not
  derive `accessibilityFrame` from the node, so no control in the game could be
  focused by VoiceOver or activated by assistive technology;
* **list rows were not published at all**, leaving the leaderboard, stats and
  achievements unreadable by a screen reader;
* a **disabled button still advertised itself as enabled**, so VoiceOver offered
  "BUY" on a skin the wallet could not afford.

`AccessibleNode` in `FlappyBird/UI/Accessibility.swift` is the fix for the first
two: it converts a node's own bounds into screen coordinates and composes a row
into one spoken sentence.

The suite is slower than the unit tests because it drives a simulator, so it is
its own Make target and its own CI step:

```bash
xcodebuild -project "Flappy Bird.xcodeproj" -scheme FlappyBird \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FlappyBirdUITests test
```

## Backend

`backend/tests/` — supertest against the real Express app, no mocks of the
storage layer.

| File | Covers |
|------|--------|
| `health.test.ts` | Probes, metrics, the discovery document, error shape |
| `auth.test.ts` | Register, login, guest, upgrade, rotation, password, deletion |
| `scores.test.ts` | Submission, stats, achievements, anti-cheat, history |
| `leaderboard.test.ts` | Ranking, ties, pagination, windows, friends, bans |
| `achievements.test.ts` | Catalog, progress, monotonic merge |
| `challenges.test.ts` | Derivation, board, best-per-day, date validation |
| `users.test.ts` | Profiles, editing, search, follow graph |
| `admin.test.ts` | Auth gate, ban, flag, delete, maintenance |
| `domain.test.ts` | Time windows, cursors, crypto, anti-cheat verdicts |
| `openapi.test.ts` | **Every route is documented, every documented route exists** |

### Both drivers, one suite

```bash
npm test                      # in-memory
DB_DRIVER=postgres npm test   # Postgres
```

This is not ceremony. Running the suite against Postgres has already caught
real divergences that the in-memory driver hid:

* a parameter reused for an `INTEGER` and a `BIGINT` column, which Postgres
  refuses to type-infer;
* tied players getting different ranks in SQL and the same rank in memory.

Against Postgres the files run serially, because each one truncates the shared
database between tests.

### The OpenAPI guard

`openapi.test.ts` enumerates the real Express routers and diffs them against the
specification in both directions, and checks that every operation has a summary,
a unique `operationId`, at least one response and a declared tag. Adding an
endpoint without documenting it fails the build.

## Writing a test

**Swift** — isolate storage:

```swift
let store = TestSupport.makeStore()          // its own UserDefaults suite
_ = store.record(run: TestSupport.run(score: 25), mode: .classic, deathCause: .pipe)
XCTAssertEqual(store.profile.bestScore(for: .classic), 25)
```

**Backend** — use the helpers; `runPayload` builds a run that passes every
anti-cheat heuristic, so a test about scoring is not accidentally a test about
plausibility:

```ts
const app = await freshApp();                 // empty storage + a fresh app
const session = await registerUser(app, 'runner');
const response = await submitRun(app, session, 42);
expect(response.body.rank).toBe(1);
```

## Coverage

```bash
make api-coverage     # backend/coverage/index.html
```

CI uploads it as an artifact on every run.

## What is deliberately not tested

* **SpriteKit rendering.** Snapshot-testing a particle system is expensive and
  brittle; `make media` produces real screenshots instead, which a human reads.
* **Third-party behaviour.** Express routing, `pg` and bcrypt are assumed to work.
* **The network layer end-to-end.** `make smoke` covers that against a real
  server rather than a pile of URL-protocol mocks.
