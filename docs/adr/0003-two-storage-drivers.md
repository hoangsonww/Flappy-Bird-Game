# 3. Two storage drivers, one test suite

**Status:** accepted · **Date:** 2026-03-19

## Context

The backend needs durable storage, which means Postgres. But requiring Postgres
to run the API makes the first experience "install Docker" — the same problem
[ADR 1](0001-optional-backend.md) solves for the game.

The usual answer is SQLite, which brings a native module and a second SQL
dialect to keep working.

## Decision

The storage layer is defined by repository interfaces with two implementations:

* **`postgres`** — the real schema, used in Docker and in production.
* **`memory`** — plain TypeScript data structures, the default for `npm run dev`
  and for tests.

The in-memory driver is not a stub. It implements the same contracts with the
same semantics, including the leaderboard rules: only unflagged runs from
unbanned players, one row per player, ties sharing a rank.

**The entire test suite runs against both**, locally (`make api-test-pg`) and in
CI as a 2×2 matrix with Node 20 and 22.

## Consequences

**Good.** `npm install && npm run dev` gives a fully functional API with zero
infrastructure. Tests are fast by default. Contributors working on the game's
networking never need a database.

**It has already paid for itself.** Running the suite against Postgres caught
two real bugs the in-memory driver hid:

1. a parameter reused for an `INTEGER` and a `BIGINT` column in the same
   `INSERT`, which Postgres refuses to type-infer (`inconsistent types deduced
   for parameter $2`);
2. ties getting distinct ranks in SQL but shared ranks in memory, because
   `RANK() OVER (ORDER BY score DESC, submitted_at ASC)` never sees a tie.

Both would have shipped as "works on my machine".

**Costs.** Every repository method is written twice, and a behavioural change has
to land in both. The shared test suite makes that a mechanical, verified process
rather than a hopeful one. `DB_DRIVER=memory` is refused in production.
