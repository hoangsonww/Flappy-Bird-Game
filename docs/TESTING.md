# Testing

228 tests: **122 Swift** and **106 backend**, the latter run against both
storage drivers.

```bash
make test         # Swift
make api-test     # backend, in-memory
make api-test-pg  # backend, Postgres
make check        # everything CI runs except the iOS build
```

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
| `GhostRecorderTests` | Sampling rate, clamping, interpolation, caps |
| `PersistenceTests` | Runs, wallet, skins, achievements, ghost, reset |
| `AchievementSystemTests` | Every unlock path, including the client-only ones |
| `DailyChallengeHelperTests` | **Byte-for-byte parity with the server** |
| `BackendClientTests` | URL normalisation, discovery order, DTO decoding |
| `AuthStoreTests` | Session storage when the Keychain is unavailable |
| `ThemeTests` | Skins, time-of-day cycle, weather weighting, font fallback |

Two of these are contract tests rather than unit tests:

* **`DailyChallengeHelperTests`** pins four dates against values produced by the
  server's TypeScript. If either implementation drifts, players would silently
  get different challenges — so the test fails instead.
* **`AuthStoreTests`** exists because a silent Keychain failure once left the app
  looking connected while never uploading anything. The contract is now explicit:
  a stored session is always usable in-process.

```bash
xcodebuild -project "Flappy Bird.xcodeproj" -scheme FlappyBird \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
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
