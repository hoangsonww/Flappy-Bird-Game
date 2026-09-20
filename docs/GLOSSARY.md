# Glossary

Terms used across the code and these documents, in one place. Where a term has a
specific meaning *in this project* that differs from its general use, that is
called out.

---

## Gameplay

**Combo** — consecutive coins collected without missing one. Drives the coin
multiplier, capped at ×8. Note it advances on **coins, not pipes**, so a combo
can exceed the score; an anti-cheat rule once got this wrong.

**Daily challenge** — a mode whose world is derived from the date, identically
on every device and in both languages. See [Determinism](DETERMINISM.md).

**Gap** — the vertical opening between a pipe pair. 170 pt at the easiest
setting, floored at 118 pt. The bird's collision circle is 36 pt across, so read
it as clearance rather than as a raw number.

**Medal** — bronze / silver / gold / platinum, awarded by score at the end of a
run.

**Mode** — Classic, Endless, Time Attack, Hardcore, Zen or Daily. They differ in
gap, scroll speed, gravity, whether they ramp and whether they are lethal.

**Pitch** — the horizontal distance between one pipe pair and the next, in
points. Derived: `spawnInterval / scrollRate`.

**Ramp** — whether a mode's difficulty increases with pipes passed. Classic and
Zen **do not ramp**; they sit at their starting values for the whole run.

**Reaction window** — the seconds between one gap and the next, i.e.
`spawnInterval`. The number that decides whether the game feels fair.

**Run** — one attempt, from the first tap to death or the clock running out.

---

## Engine

**Atlas** — a folder of images Xcode compiles into a single texture, so sprites
sharing it batch into one draw call. The bird's four frames live in
`bird.atlas`.

**Draw call** — one batch of geometry sent to the GPU. The number to watch;
node count tracks how much *exists*, draw count tracks what it *costs*.

**Effective z** — a node's `zPosition` **plus all its ancestors'**. Ties have no
defined draw order, which is a bug source. See [Rendering](RENDERING.md).

**Nine-slicing** — `centerRect` on an `SKSpriteNode`: the edges stay
pixel-perfect and only the centre stretches. How pipes reach any screen height
with a crisp cap.

**Scene** — an `SKScene`. Navigation is presenting a new one into the single
`SKView`; there is no navigation controller.

**`worldNode`** — the container for everything that scrolls. `speed = 0` freezes
it all, which is how pause and slow motion are each one line.

---

## Persistence

**Pending upload** — a run queued for the server. Lives in `pendingUploads`
*and* in `recentRuns`; both have to be updated when it is acknowledged.

**Profile** — the `PlayerProfile` document under `player.profile.v2`: scores,
wallet, skins, achievements, history and the upload queue.

**Replay** — a recorded run: bird frames at 30 Hz plus one entry per obstacle
spawn. Stored under its own key, never sent to the server.

**Seed** — the value a run's world is generated from. Stored with every run.

---

## Backend

**Driver** — the storage implementation: `postgres` or `memory`. Both satisfy
the same repository contracts and the whole suite runs against each.

**Flagged** — a run stored but hidden from leaderboards because a plausibility
check fired. Distinct from **rejected**, which is refused outright with a 422.

**Guest account** — an account created automatically from the device id, so
leaderboards work without a sign-up form. Can be upgraded in place.

**Repository** — the data-access layer. The only thing that knows whether it is
talking to Postgres or memory.

**Window** — a leaderboard time range: all-time, today, week or month.

---

## Tooling

**ADR** — Architecture Decision Record, in [`docs/adr/`](adr/). Why something is
the way it is, written down at the time.

**Attract mode** — `-demo`, where the auto-pilot flies. Used for capture, not
shipped as a feature.

**Conventional Commits** — the commit format the release version is derived
from, so the prefix genuinely matters.

**Generated project** — `project.pbxproj` is produced by
`scripts/generate_xcodeproj.py` from the files on disk, never hand-edited. CI
fails if it is stale.

**Seeded demo data** — `-seed-demo`, a fabricated profile so captures and tests
are reproducible. Never uploaded.

---

## Accessibility

**`AccessibleNode`** — an `SKNode` subclass that computes a real
`accessibilityFrame` in screen coordinates, because SpriteKit does not.

**Accessibility element** — a node published to the accessibility tree. **It
hides its children**, so a row containing a button must not be one.

**Element type** — SpriteKit publishes `SKLabelNode` as `.other`, *not*
`.staticText`. `app.staticTexts` matches nothing in this app.

---

## Where to look next

- [Architecture](../ARCHITECTURE.md) — the map these terms sit on
- [Gameplay](GAMEPLAY.md) — the rules in full
- [Testing](TESTING.md) — how the terms show up in tests
