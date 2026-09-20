# 1. The backend is optional

**Status:** accepted · **Date:** 2026-03-19

## Context

The project needed leaderboards and cloud saves. The obvious implementation —
an app that talks to a server — makes the server a hard dependency: clone the
repo, and before you can play you need Docker, a database and a migration step.

For a game whose entire appeal is "tap to flap", that is a terrible first
experience, and it makes the repository much harder to evaluate.

## Decision

The backend is strictly additive. The game is fully playable with no server:
scores, coins, skins, achievements and even the daily
challenge all work offline.

Concretely:

* the game never blocks on the network — discovery runs in the background and
  only ever *enables* extra UI;
* every online feature has an offline equivalent (the leaderboard screen shows
  local scores; the daily challenge is derived locally from the same hash);
* runs queue locally and upload when a server appears;
* a server is only accepted after a `protocol: "flappy-bird/1"` handshake, so
  pointing at the wrong port fails clearly instead of producing odd errors.

## Consequences

**Good.** `git clone && open && ⌘R` is the whole setup. The backend can be
developed, tested and broken without affecting the game. The offline path is not
a degraded mode that rots — it is the default, so it stays working.

**Costs.** Some logic exists twice: the achievement catalog and the daily
challenge derivation are implemented in both Swift and TypeScript. This is
mitigated with contract tests that pin the two implementations against the same
values — `DailyChallengeHelperTests` fails if either side drifts.

The sync also has to be conflict-free, which forced monotonic merge rules
(progress only increases, unlock timestamps are never overwritten). That turned
out to be a simplification rather than a cost.
