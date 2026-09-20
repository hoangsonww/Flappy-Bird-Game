# FAQ

### Do I need the backend?

No. Clone, open in Xcode, press ⌘R. Scores, coins, skins and achievements all
save locally. The backend adds accounts, leaderboards and cloud saves, and the
game finds it automatically when it is running.

### How does the game know the server is there?

On launch it probes a short list of URLs — the one in Settings, then
`FlappyBackendURL` from `Info.plist`, then `localhost:4000` — and calls
`GET /v1/meta/config`. A response containing `"protocol": "flappy-bird/1"`
switches on the online features. Anything else and it stays offline. Nothing
blocks on this; discovery runs in the background.

### What happens to my scores while I am offline?

They queue locally (up to 200 runs) and upload when a server reappears. Zen runs
never upload — a mode you cannot lose would flatten the leaderboards.

### Why is there an in-memory storage driver?

So `npm run dev` works with no Docker and no Postgres. It implements the same
repository contracts as the Postgres driver, and **the entire test suite runs
against both** — which has already caught real differences between them.

### Why is the Xcode project generated?

Because `project.pbxproj` is a terrible thing to merge. `scripts/generate_xcodeproj.py`
derives it from the files on disk with deterministic object IDs, so adding a file
is `touch` + `make xcodegen`, and two branches adding files do not conflict. CI
fails if the checked-in project is stale.

### Where do the sound effects come from?

They are synthesised at launch — square and triangle waves rendered into PCM
buffers by `AudioManager`. No audio assets to download, no licensing questions,
and the chiptune character is intentional.

### How is the daily challenge the same for everyone?

Its parameters come from `SHA-256("flappy-bird-daily:YYYY-MM-DD")`. The identical
function runs in Swift and in TypeScript, and a test pins four dates against
values produced by the server, so the two cannot drift. The challenge therefore
exists offline; the server is only needed to compare scores.

### Is the anti-cheat real?

Partly, and the docs say so plainly. Impossible runs are rejected, improbable
ones are flagged and kept off leaderboards, and runs can be HMAC-signed. But the
signing secret ships inside the app, so a determined person can extract it. It
raises the cost of casual scripting; it does not make the leaderboard
tamper-proof.

### Can I edit my local save?

Yes, trivially, on a jailbroken device. It does not matter: the server never
trusts the client's idea of a personal best — it recomputes ranks from submitted
runs.

### Why Express and not Fastify / Hono / …?

Familiarity beats benchmarks for a project whose peak load is one household.
Express 5 handles async errors natively, which removes the main reason people
used to reach for a wrapper.

### How do I run the backend on my phone's network?

`ipconfig getifaddr en0` on the Mac, then put `http://192.168.x.x:4000` into
Settings ▸ Server ▸ Server URL. Same Wi-Fi, no firewall on port 4000.

### How are releases versioned?

From Conventional Commits. `feat` → minor, `fix`/`perf`/`revert` → patch, `!` or
`BREAKING CHANGE` → major, anything else → no release. Preview it with
`node scripts/release.mjs`.

### How were the screenshots made?

`make media`. The app accepts launch arguments to open any screen directly, so
the capture is reproducible rather than a manual tapping session.

### Can I use this as a starting point?

Yes — MIT. If you ship a public instance, replace the JWT secrets, put TLS in
front of the API, and read [the security model](SECURITY-MODEL.md) first.

### Is this affiliated with the original Flappy Bird?

No. It is an independent tribute built for learning, with original code and a
very different feature set.
