# Screens and navigation

Every screen in the game, how you get there, and what it is built from. There is
no navigation controller and no storyboard — navigation is presenting a new
`SKScene` into the one `SKView`.

---

## The map

```mermaid
flowchart TB
    Launch(["Launch"]) --> Menu["<b>MenuScene</b><br/>mode selector · wallet · status"]

    Menu -->|PLAY| Game["<b>GameScene</b><br/>the only scene with a frame loop"]
    Menu -->|LEADERBOARD| LB["LeaderboardScene"]
    Menu -->|ACHIEVEMENTS| Ach["AchievementsScene"]
    Menu -->|SHOP| Shop["ShopScene"]
    Menu -->|STATS| Stats["StatsScene"]
    Menu -->|REPLAYS| Rep["ReplaysScene"]
    Menu -->|SETTINGS| Set["SettingsScene"]

    Game -->|pause ▸ MENU| Menu
    Game -->|summary ▸ MENU| Menu
    Game -->|PLAY AGAIN| Game

    Rep -->|tap a row| Play["<b>ReplayScene</b>"]
    Play -->|‹| Rep

    LB & Ach & Shop & Stats & Set -->|‹| Menu

    style Game fill:#fef3c7,stroke:#d97706,color:#92400e
    style Play fill:#e0e7ff,stroke:#4f46e5,color:#312e81
    style Menu fill:#d1fae5,stroke:#059669,color:#065f46
```

Every screen is one push away from the menu. There is no deep stack to unwind,
which is why a single `‹` is always enough.

---

## Two kinds of screen

```mermaid
flowchart LR
    subgraph Live["GameScene · ReplayScene"]
        L1["frame loop"]
        L2["scrolling world"]
        L3["physics (game only)"]
    end

    subgraph Static["Everything else"]
        S1["ListScene base class"]
        S2["dark background"]
        S3["built once on open"]
    end

    style Live fill:#fef3c7,stroke:#d97706,color:#92400e
```

The distinction matters for cost: list screens build their content once and then
do nothing per frame, which is why they open instantly and why they share a base
class.

---

## `ListScene`

The shared chrome for every full-screen list: title, back button, optional
filter chips, a scroll area and a status line for empty and error states.

```mermaid
flowchart TB
    subgraph ListScene
        H["header · title + ‹"]
        C["segments · filter chips"]
        S["ScrollContainer"]
        St["statusLabel"]
    end

    Sub["Subclass"] -->|"overrides screenTitle"| H
    Sub -->|"overrides segments"| C
    Sub -->|"overrides buildContent() → setRows()"| S
    Sub -->|"showStatus() when empty"| St
```

A subclass supplies a title, optional segments, and rows. `makeRow` builds the
standard badge / title / subtitle / value layout **and** publishes it as one
accessibility element — see [Accessibility](ACCESSIBILITY.md).

| Screen | Segments |
|--------|----------|
| Leaderboard | ALL TIME · TODAY · WEEK · MONTH |
| Achievements | ALL · UNLOCKED · LOCKED |
| Stats | TOTALS · BY MODE · RECENT |
| Settings | GAME · ACCESS · SERVER |
| Replays | — |

---

## The menu

<div align="center">
  <img src="../img/screens/menu.png" alt="The main menu" width="260" />
  <br/>
  <sub>Captured by `make media`, straight from the simulator.</sub>
</div>

```mermaid
flowchart TB
    T["FLAPPY BIRD"] --> P["preview bird<br/><i>wearing the selected skin</i>"]
    P --> Card["mode card<br/>◀ &nbsp; SYMBOL NAME &nbsp; ▶<br/>subtitle · best"]
    Card --> Play["PLAY"]
    Play --> Grid["2 × 3 grid<br/>LEADERBOARD · ACHIEVEMENTS<br/>SHOP · STATS<br/>REPLAYS · SETTINGS"]
    Grid --> Foot["wallet · connection status"]
```

Two details worth knowing:

**The mode card fits its own text.** Labels are centred on the card, so the
usable width is the gap *between the arrows*, not the panel width. `fit(_:)`
shrinks a label until it fits that gap — long subtitles used to run underneath
the arrows.

**The grid is 2 × 3.** Settings used to sit apart as a full-width button;
folding it in kept every row the same shape when Replays joined, rather than
leaving an orphan cell.

---

## The game screen

<div align="center">
  <img src="../img/screens/gameplay.png" alt="A run in progress" width="260" />
  <br/>
  <sub>The HUD: score, level, wallet, pause. Everything else is the world.</sub>
</div>

```mermaid
stateDiagram-v2
    [*] --> Ready: enterReadyState()
    Ready --> Playing: tap
    Playing --> Paused: pause button / lost focus
    Paused --> Playing: RESUME
    Paused --> [*]: MENU
    Playing --> Dying: lethal contact
    Dying --> GameOver: after 0.85 s
    GameOver --> Ready: PLAY AGAIN
    GameOver --> [*]: MENU
```

The HUD carries the score, best, coins, combo, active power-ups, the mode name,
the connection dot and the pause button. Its right-hand column — pause, mode,
status dot — is aligned to one edge; letting each element pick its own inset is
how "CLASSIC" ended up hanging 46 pt short of the button above it.

`Dying` exists so the death animation and the red flash have a beat before the
summary panel appears.

---

## The summary panel

<div align="center">
  <img src="../img/screens/gameover.png" alt="The end-of-run summary" width="260" />
  <br/>
  <sub>The panel sizes itself from its row count.</sub>
</div>

```mermaid
flowchart TB
    Title["GAME OVER · or · NEW BEST!"] --> Cause["cause of death"]
    Cause --> Score["the score, large"]
    Score --> Medal["medal chip &nbsp;·&nbsp; BEST n"]
    Medal --> Rows["pipes · coins · combo · time<br/>+ rank or sync state"]
    Rows --> Retry["PLAY AGAIN"]
    Retry --> Sec["MENU &nbsp; SHARE"]
```

The panel **sizes itself from its row count**. It used to be a hardcoded 372 or
400 points, which was about 26 pt short of the content — the MENU/SHARE row
rendered two points *below* the card's own bottom edge. `height(forRows:)`
derives it now, and `GameOverPanelTests` pins every variant.

---

## The replay screen

<div align="center">
  <img src="../img/screens/replays.png" alt="The saved replays list" width="260" />
  <br/>
  <sub>The list that feeds the replay screen — every row is a real recording.</sub>
</div>

```mermaid
flowchart TB
    Banner["▶ REPLAY<br/><i>never mistakable for live play</i>"] --> Sum["MODE · n pts · n c"]
    Sum --> World["the recorded run<br/><i>no physics</i>"]
    World --> Tray["transport tray"]
    Tray --> Bar["progress bar + 0.0s / 44.0s"]
    Bar --> Btns["PAUSE &nbsp; RESTART"]
```

The transport sits on its own translucent panel. It overlays whatever the replay
happens to be showing — pale sand, in a run that ends near the ground — and a
thin progress bar and a small clock are unreadable against that.

Detail in [Replays](REPLAYS.md).

---

## Opening a screen directly

Every screen has a launch argument, which is what makes screenshots and UI tests
reproducible:

```bash
xcrun simctl launch booted com.hoangsonww.flappybird -screen shop -seed-demo
xcrun simctl launch booted com.hoangsonww.flappybird -screen stats -segment 2
```

| Argument | Effect |
|----------|--------|
| `-screen <name>` | `menu`, `game`, `leaderboard`, `achievements`, `shop`, `stats`, `replays`, `settings` |
| `-segment <n>` | Pre-select a filter chip |
| `-mode <name>` | Force a game mode |
| `-seed-demo` | Populate a believable profile |
| `-demo` | Attract mode — the bird plays itself |
| `-demo-die <s>` | End an attract run on cue |
| `-debug-hud` | Overlay live state, velocity and the targeted gap |

Full table in [Configuration](CONFIGURATION.md).

---

## Where to look next

- [Rendering](RENDERING.md) — how these scenes are drawn
- [Accessibility](ACCESSIBILITY.md) — how they reach VoiceOver
- [Gameplay](GAMEPLAY.md) — what the numbers on them mean
- [Testing](TESTING.md) — the UI suite that drives every one of them
