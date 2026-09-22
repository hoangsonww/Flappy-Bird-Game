# Troubleshooting

Start here:

```bash
make doctor
```

## The game

### The project will not open, or Xcode shows missing files

The `.pbxproj` is generated. Regenerate it:

```bash
make xcodegen
```

If you added a Swift file and it is not being compiled, that is the fix — the
file is only in the target after regeneration.

### "You have not agreed to the Xcode license agreements"

```bash
sudo xcodebuild -license accept
```

### No simulator is available

Xcode ▸ Settings ▸ Components ▸ install an iOS simulator runtime, then:

```bash
xcrun simctl list devices available
SIMULATOR="iPhone 16 Pro" make run
```

### The build fails with a code-signing error

Every `make` target passes `CODE_SIGNING_ALLOWED=NO`, which is enough for the
simulator. For a real device, open the project and set your team under
Signing & Capabilities; the bundle identifier `com.hoangsonww.flappybird` is
likely already taken, so change it to something of your own.

### No sound

Sound effects are synthesised at launch, so there is nothing to download —
check Settings ▸ Game ▸ Sound effects, the simulator's own volume, and whether
the Mac is muted. The audio session is `.ambient`, so it deliberately mixes with
(and yields to) whatever else is playing.

### The game feels different from the original

Check the mode. Hardcore uses tighter gaps and heavier gravity; Zen is
intentionally floaty. Classic matches the original tuning.

### Progress disappeared

`Settings ▸ Game ▸ Reset local progress` wipes everything, as does deleting the
app. Runs already uploaded survive on the server and are visible on the
leaderboard, but local coins, skins and achievements do not come back.

## The backend

### The game says "No server found"

```bash
make health        # is it running at all?
make up            # start it
make logs          # what does it say?
```

Then, in the game, Settings ▸ Server ▸ **Reconnect**.

### Running on a real device

`localhost` is the phone, not your Mac. Find your Mac's LAN address:

```bash
ipconfig getifaddr en0
```

Enter `http://192.168.x.x:4000` in Settings ▸ Server ▸ Server URL, and make sure
both devices are on the same network and no firewall blocks port 4000.

### "That server is not a Flappy Bird backend"

The URL answered, but `/v1/meta/config` did not return
`protocol: "flappy-bird/1"`. You are pointing at something else — check the port.

### Scores are not uploading

In order:

1. Settings ▸ Server — does it say **Connected**?
2. Is there an account? Guest accounts are created automatically, but only if
   `ENABLE_GUEST_ACCOUNTS` is true on the server.
3. Settings ▸ Server ▸ **Pending uploads** shows the queue. Tap **SYNC**.
4. Zen runs are never uploaded, by design.

The summary panel also names the reason: `queued · no server`,
`queued · signed out`, or the server's own error.

### A run came back flagged

The server thought it was implausible. The panel and the API response list the
reasons — usually a run far too short for the number of pipes. Flagged runs are
stored but kept off leaderboards. See
[fair play](BACKEND.md#fair-play).

### Port 4000 is already in use

```bash
lsof -i :4000
BACKEND_PORT=4100 make up   # or set it in .env
```

Then point the game at `http://localhost:4100`.

### The backend container keeps restarting

```bash
make logs
```

Common causes: Postgres not healthy yet (compose waits, so this usually means
the database itself failed), or a missing JWT secret in production mode.

### Migration drift

```
Migration drift detected in 001_init.sql: the file changed after it was applied.
```

An applied migration was edited. Either restore the file, or reset the database
if it holds nothing you need:

```bash
make clean-volumes && make up
```

### Tests fail against Postgres but pass in memory

That is the point of running both — it is usually a real difference. Check for
SQL type ambiguity (a parameter reused for an `INTEGER` and a `BIGINT` column)
or an ordering assumption. Against Postgres the files run serially because each
truncates the shared database.

```bash
make up-db
cd backend && DB_DRIVER=postgres npx vitest run tests/leaderboard.test.ts
```

## Docker

### Compose cannot pull an image

Usually transient. Retry, or pull the base images explicitly:

```bash
docker pull node:22-alpine
docker pull postgres:16-alpine
docker pull docker/dockerfile:1.7
```

### The build is slow

Only the first time — the dependency layer is cached afterwards. `make clean` does
not touch Docker; use `docker builder prune` if you really want a cold build.

## CI

### "Xcode project is out of date"

```bash
make xcodegen && git add "Flappy Bird.xcodeproj" && git commit --amend
```

### The release workflow did not produce a release

By design, if no commit since the last tag was a `feat`, `fix`, `perf`, `revert`
or a breaking change. Check with:

```bash
node scripts/release.mjs
```

## Still stuck?

Open an issue with the output of `make doctor`, what you expected, what happened,
and — if the backend is involved — `make logs`. Game-side logs:

```bash
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.hoangsonww.flappybird"'
```
