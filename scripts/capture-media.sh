#!/usr/bin/env bash
#
# Capture screenshots from the iOS Simulator.
#
# The app exposes launch switches (see FlappyBird/Core/LaunchOptions.swift) so
# every screen can be opened directly and the bird can fly itself — which makes
# this reproducible rather than a manual tapping session.
#
#   ./scripts/capture-media.sh
#   SIMULATOR="iPhone 17 Pro" ./scripts/capture-media.sh
#
# Output: img/screens/*.png
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SIMULATOR="${SIMULATOR:-iPhone 17 Pro}"
BUNDLE_ID="com.hoangsonww.flappybird"
SCHEME="FlappyBird"
PROJECT="Flappy Bird.xcodeproj"
DERIVED="${DERIVED:-build/DerivedData}"
SHOT_DIR="img/screens"

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
  local target="$SHOT_DIR/$name.png"

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 0.6
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" >/dev/null
  sleep "$wait_for"

  # The simulator sometimes hands back a frame whose Dynamic Island has not
  # been composited, leaving a black bar across the top. A discarded warm-up
  # capture makes it rare; verifying and retrying makes it impossible to commit.
  local attempt
  for attempt in 1 2 3 4; do
    xcrun simctl io "$UDID" screenshot --type=png /tmp/flappy-warmup.png >/dev/null 2>&1
    sleep 0.4
    xcrun simctl io "$UDID" screenshot --type=png "$target" >/dev/null 2>&1
    if python3 "$REPO_ROOT/scripts/verify-capture.py" "$target" >/dev/null 2>&1; then
      break
    fi
    [ "$attempt" = 4 ] && fail "$target kept coming back mid-composite"
    info "Recomposite — retaking $name (attempt $((attempt + 1)))"
    sleep 1
  done

  rm -f /tmp/flappy-warmup.png
  ok "Captured $target"
}

# ── Screenshots ──────────────────────────────────────────────────────────────
info "Capturing screens…"
# The auto-pilot needs a few seconds of runway before a screen is worth showing,
# and hardcore mode is used for the game-over shot because its tighter gaps end
# a run in seconds rather than in a minute.
shoot "menu"         3   -seed-demo
shoot "gameplay"     7   -seed-demo -demo
shoot "leaderboard"  4   -seed-demo -screen leaderboard
shoot "achievements" 4   -seed-demo -screen achievements
shoot "shop"         4   -seed-demo -screen shop
shoot "stats"        4   -seed-demo -screen stats
shoot "settings"     4   -seed-demo -screen settings
shoot "replays"      4   -seed-demo -screen replays
# `-demo-die` ends the run on cue; waiting for the auto-pilot to crash meant
# the shot caught the summary panel only on the runs where it happened to die
# inside the window.
shoot "gameover"    17   -seed-demo -demo -demo-die 12 -mode hardcore

xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

ok "Done. Screens in $SHOT_DIR"
