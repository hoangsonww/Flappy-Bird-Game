# Architecture

## The shape of the project

Two independent halves that know as little as possible about each other:

```mermaid
flowchart TB
    subgraph Game["iOS game — Swift + SpriteKit"]
        direction TB
        Scenes["Scenes<br/>Menu · Game · Leaderboard · Shop · Stats · Settings"]
        Systems["Systems<br/>difficulty · power-ups · weather · achievements · replays"]
        Entities["Entities<br/>Bird · PipePair · Collectible · ParallaxWorld"]
        Store["GameStore + Settings<br/>UserDefaults"]
        Online["OnlineService<br/>discovery · sync queue"]

        Scenes --> Systems --> Entities
        Scenes --> Store
        Scenes --> Online
        Online --> Store
    end

    subgraph Backend["Backend — Node.js + TypeScript (optional)"]
        direction TB
        Routes["Routes<br/>/v1/auth · /scores · /leaderboard · /achievements · /challenges"]
        Services["Services<br/>tokens · scores · anti-cheat · events"]
        Repos["Repositories<br/>interface"]
        PG[("PostgreSQL")]
        Mem[["In-memory driver"]]

        Routes --> Services --> Repos
        Repos --> PG
        Repos --> Mem
    end

    Online -. "HTTP/JSON<br/>only when reachable" .-> Routes

    style Game fill:#ecfdf5,stroke:#059669,color:#064e3b
    style Backend fill:#eff6ff,stroke:#2563eb,color:#1e3a8a
```

The dotted line is the whole relationship. The game holds a `URL` and some
`Codable` structs; the backend has never heard of SpriteKit.

## Source layout

```
FlappyBird/
├── App/          UIApplication + the single view controller
├── Core/         config, modes, state, RNG, audio, haptics, persistence, theme
├── Entities/     the things you see: Bird, PipePair, Collectible, ParallaxWorld
├── Systems/      the rules: difficulty, power-ups, weather, achievements, replays
├── UI/           reusable nodes: buttons, panels, HUD, scroll container, toasts
├── Scenes/       one file per screen
└── Backend/      the optional client: discovery, HTTP, models, sync

backend/
├── src/
│   ├── routes/          one file per resource, thin — validation + delegation
│   ├── services/        the logic worth testing on its own
│   ├── repositories/    storage contracts + two implementations
│   ├── domain/          entities, the achievement catalog, challenge derivation
│   ├── middleware/       auth, validation, rate limits, metrics, errors
│   └── config/          environment, logging, constants shared with the game
├── migrations/          forward-only SQL
├── openapi/             the API contract
└── tests/               106 tests, run against both storage drivers
```

## One frame of the game loop

`GameScene.update(_:)` is the only place per-frame work happens. It is ordered
so that later steps see the results of earlier ones:

```mermaid
sequenceDiagram
    autonumber
    participant SK as SpriteKit
    participant GS as GameScene
    participant PU as ActivePowerUps
    participant WS as WeatherSystem
    participant DC as DifficultyCurve
    participant B as Bird

    SK->>GS: update(currentTime)
    GS->>GS: delta = min(1/20, now - last)
    GS->>PU: expire(now) · refresh HUD badges
    GS->>WS: update(delta) → wind vector
    WS-->>B: applyImpulse(wind)
    GS->>DC: snapshot(pipesPassed)
    DC-->>GS: gap · spawn interval · scroll rate · gravity
    GS->>GS: spawn a pair when the accumulator is full
    GS->>GS: magnet pulls nearby coins
    GS->>B: clamp velocity and lateral drift
    SK->>GS: didBegin(contact)
    GS->>GS: score gate · coin · power-up · pipe · ground
```

Two details that matter:

* **`delta` is clamped to 1/20 s.** A dropped frame must not teleport the bird
  through a pipe.
* **`worldNode.speed` is the single time lever.** Pausing sets it to `0`;
  slow-motion sets it to `0.55`. Nothing else has its own notion of paused,
  which is what keeps the ground, the sky and the pipes from drifting apart.

## Difficulty

The curve is bounded on purpose — a long run should stay hard but never become
impossible:

```mermaid
flowchart LR
    P["pipes passed"] --> T["t = 1 − (1 − min(1, pipes/40))³"]
    T --> G["gap: start → start − 44<br/>floor 104 pt"]
    T --> S["spawn: 1.90 s → 1.05 s"]
    T --> R["scroll: 0.0100 → 0.0062 s/pt"]

    style T fill:#fef3c7,stroke:#d97706,color:#92400e
```

Ease-out cubic: most of the difficulty arrives in the first 40 pipes, then it
plateaus. `classic` and `zen` opt out of ramping entirely.

## Talking to the backend

The game never blocks on the network. Discovery runs in the background, and the
result only ever *enables* extra UI.

```mermaid
stateDiagram-v2
    [*] --> Disabled: online features off
    [*] --> Searching: launch

    Searching --> Online: GET /v1/meta/config<br/>protocol == "flappy-bird/1"
    Searching --> Offline: nothing answered

    Online --> Offline: request fails
    Offline --> Searching: foreground · Reconnect
    Disabled --> Searching: enabled in Settings

    Online --> Online: flush queued runs

    note right of Offline
        Runs keep accumulating in
        pendingUploads and upload
        when a server reappears.
    end note
```

Candidate URLs are tried in order: the URL typed into Settings, then
`FlappyBackendURL` from `Info.plist`, then `http://localhost:4000`, then
`http://127.0.0.1:4000`. A server is only accepted if it answers with
`protocol: "flappy-bird/1"`, so pointing the game at an unrelated service fails
immediately and clearly instead of producing confusing errors later.

## Storage

Both sides store the same shapes, which is what makes the sync trivial.

| | Game (offline) | Backend |
|---|---|---|
| Runs | `PlayerProfile.recentRuns` (last 50) | `scores` table |
| Aggregates | `LifetimeStats` | `user_stats`, maintained on insert |
| Achievements | `[code: AchievementProgress]` | `user_achievements` |
| Queue | `pendingUploads` (max 200) | — |
| Format | one JSON document in `UserDefaults` | normalised SQL |

The merge rules are monotonic in both directions: progress only increases, an
unlock timestamp is never overwritten. Replaying an old payload is a no-op,
which means the sync needs no coordination and no conflict resolution.

## Design decisions

Recorded in full under [`adr/`](adr/):

1. [The backend is optional](adr/0001-optional-backend.md)
2. [The Xcode project is generated](adr/0002-generated-xcode-project.md)
3. [Two storage drivers, one test suite](adr/0003-two-storage-drivers.md)
