# Roadmap

Ideas, roughly ordered. Nothing here is a commitment — and the "not planned"
section is as important as the rest.

## Gameplay

- [ ] **A replay mode** — a run's seed already reproduces its world exactly, so
      a recorded flight path could be replayed as its own screen. The previous
      attempt drew the replay into the live scene, where a second translucent
      bird read as a rendering fault; it belongs in a mode of its own.
- [ ] **Seasonal events** — themed skins and a modifier, driven by the same
      deterministic derivation as the daily challenge.
- [ ] **A second obstacle type** — moving platforms or a rotating gap, restricted
      to the harder modes.
- [ ] **Local two-player** — same device, alternating runs, shared leaderboard.
- [ ] **Replay export** — turn a recorded run into a shareable clip.

## Presentation

- [ ] **A bundled pixel font**, so the retro look does not depend on what the
      device happens to have installed.
- [ ] **Parallax depth for the city layer** — one more scroll rate.
- [ ] **Richer death animation** — the feather burst could carry more weight.
- [ ] **Dynamic Island / Live Activity** for a run in progress.

## Backend

- [ ] **Seasons** — leaderboards that reset on a schedule, with an archive.
- [ ] **Clans or groups** — the friend graph is already one-directional and could
      grow a second edge type.
- [ ] **Push notifications** when your rank is beaten.
- [ ] **Redis** for leaderboard caching, once a single Postgres query stops being
      fast enough (it is currently nowhere near that point).
- [ ] **Read replicas** — same caveat.

## Developer experience

- [ ] **A Swift Package** for the shared constants (game modes, skins, achievement
      codes), generated from one source rather than mirrored by hand.
- [ ] **Snapshot tests** for the scenes, if a stable way to do it appears.
- [ ] **A TestFlight pipeline**, which needs signing secrets the repository does
      not have.

## Not planned

- **In-app purchases.** Coins are earned, and that is the whole economy.
- **Ads.** No.
- **Accounts as a requirement.** The game must always work offline and anonymous.
- **Server-authoritative simulation.** Replaying every run server-side would be
  the only real anti-cheat, and it is wildly disproportionate here. The current
  approach — reject the impossible, flag the improbable, keep the evidence — is
  documented honestly instead.
- **A cross-platform rewrite.** SpriteKit is the point.

## Contributing

Pick anything above, or bring your own idea — open an issue first for anything
large. See [DEVELOPMENT.md](DEVELOPMENT.md) and
[CONTRIBUTING.md](../.github/CONTRIBUTING.md).
