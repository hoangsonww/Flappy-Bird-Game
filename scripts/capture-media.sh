#!/usr/bin/env bash
#
# Capture screenshots and a gameplay recording from the iOS Simulator.
#
# The app exposes launch switches (see FlappyBird/Core/LaunchOptions.swift) so
# every screen can be opened directly and the bird can fly itself — which makes
# this reproducible rather than a manual tapping session.
#
#   ./scripts/capture-media.sh                      # screenshots + GIF
#   SIMULATOR="iPhone 17 Pro" ./scripts/capture-media.sh
#   SKIP_VIDEO=1 ./scripts/capture-media.sh         # screenshots only
#
# Output: img/screens/*.png, img/demo.gif, img/demo.mp4
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SIMULATOR="${SIMULATOR:-iPhone 17 Pro}"
BUNDLE_ID="com.hoangsonww.flappybird"
SCHEME="FlappyBird"
PROJECT="Flappy Bird.xcodeproj"
DERIVED="${DERIVED:-build/DerivedData}"
SHOT_DIR="img/screens"
VIDEO_SECONDS="${VIDEO_SECONDS:-26}"

info()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

command -v xcrun >/dev/null || fail "Xcode command line tools are required"

# ── Resolve the simulator ────────────────────────────────────────────────────
UDID="$(xcrun simctl list devices available \
        | grep -F "$SIMULATOR (" \
        | head -1 \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || fail "Simulator '$SIMULATOR' not found. Try: xcrun simctl list devices available"
info "Simulator: $SIMULATOR ($UDID)"

# ── Build ────────────────────────────────────────────────────────────────────
info "Building ${SCHEME}…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "id=$UDID" -configuration Debug \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/$SCHEME.app"
[ -d "$APP_PATH" ] || fail "Build product not found at $APP_PATH"
ok "Built $APP_PATH"

# ── Boot + install ───────────────────────────────────────────────────────────
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true
sleep 3

# A fixed status bar keeps screenshots consistent between runs.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 >/dev/null 2>&1 || true

info "Installing app…"
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"
ok "Installed"

mkdir -p "$SHOT_DIR"

shoot() {
  local name="$1"; shift
  local wait_for="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 0.6
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" >/dev/null
  sleep "$wait_for"
  xcrun simctl io "$UDID" screenshot --type=png "$SHOT_DIR/$name.png" >/dev/null 2>&1
  ok "Captured $SHOT_DIR/$name.png"
}

# ── Screenshots ──────────────────────────────────────────────────────────────
info "Capturing screens…"
# The auto-pilot needs a few seconds of runway before a screen is worth showing,
# and hardcore mode is used for the game-over shot because its tighter gaps end
# a run in seconds rather than in a minute.
shoot "menu"         3   -seed-demo
shoot "gameplay"    26   -seed-demo -demo
shoot "leaderboard"  4   -seed-demo -screen leaderboard
shoot "achievements" 4   -seed-demo -screen achievements
shoot "shop"         4   -seed-demo -screen shop
shoot "stats"        4   -seed-demo -screen stats
shoot "settings"     4   -seed-demo -screen settings
shoot "gameover"    22   -seed-demo -demo -mode hardcore

# ── Gameplay recording ───────────────────────────────────────────────────────
if [ "${SKIP_VIDEO:-0}" = "1" ]; then
  info "SKIP_VIDEO=1 — skipping the recording"
else
  info "Recording ${VIDEO_SECONDS}s of auto-played gameplay…"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 0.6
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -seed-demo -demo >/dev/null
  # Let the pilot build up a score so the clip opens mid-flight, not on a menu.
  sleep "${VIDEO_LEAD_IN:-12}"

  rm -f img/demo.mp4
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force img/demo.mp4 &
  RECORD_PID=$!
  sleep "$VIDEO_SECONDS"
  kill -INT "$RECORD_PID" 2>/dev/null || true
  wait "$RECORD_PID" 2>/dev/null || true
  ok "Recorded img/demo.mp4"

  if command -v ffmpeg >/dev/null; then
    info "Converting to GIF…"
    # Two-pass palette generation keeps the pixel art crisp at a small size.
    # Re-encode the MP4 first, then derive the GIF from it: one compression pass
    # feeds both, and the GIF lands comfortably under 3 MB for the README.
    ffmpeg -y -loglevel error -i img/demo.mp4 \
      -vf "scale=480:-2" -c:v libx264 -preset slow -crf 30 -pix_fmt yuv420p \
      -movflags +faststart -an /tmp/flappy-demo-small.mp4
    mv /tmp/flappy-demo-small.mp4 img/demo.mp4
    ok "Compressed img/demo.mp4 ($(du -h img/demo.mp4 | cut -f1))"

    ffmpeg -y -loglevel error -i img/demo.mp4 \
      -vf "fps=${GIF_FPS:-10},scale=${GIF_WIDTH:-280}:-1:flags=lanczos,palettegen=stats_mode=diff:max_colors=48" \
      /tmp/flappy-palette.png
    ffmpeg -y -loglevel error -i img/demo.mp4 -i /tmp/flappy-palette.png \
      -lavfi "fps=${GIF_FPS:-10},scale=${GIF_WIDTH:-280}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4" \
      -loop 0 img/demo.gif

    # Re-encode the MP4 small enough to commit and to autoplay on the landing page.
    ffmpeg -y -loglevel error -i img/demo.mp4 \
      -vf "scale=480:-2" -c:v libx264 -preset slow -crf 30 -pix_fmt yuv420p \
      -movflags +faststart -an /tmp/flappy-demo-small.mp4
    mv /tmp/flappy-demo-small.mp4 img/demo.mp4
    ok "Compressed img/demo.mp4 ($(du -h img/demo.mp4 | cut -f1))"
    ok "Wrote img/demo.gif ($(du -h img/demo.gif | cut -f1))"
  else
    info "ffmpeg not installed — keeping the MP4 only (brew install ffmpeg for a GIF)"
  fi
fi

xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

ok "Done. Screens in $SHOT_DIR, demo in img/"
