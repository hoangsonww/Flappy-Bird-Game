#!/usr/bin/env bash
#
# Build, install and launch the game in an iOS Simulator.
#
#   ./scripts/run-simulator.sh
#   SIMULATOR="iPhone 16 Pro" ./scripts/run-simulator.sh
#   SCREEN_ARGS="-seed-demo -screen shop" ./scripts/run-simulator.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SIMULATOR="${SIMULATOR:-iPhone 17 Pro}"
SCHEME="FlappyBird"
PROJECT="Flappy Bird.xcodeproj"
BUNDLE_ID="com.hoangsonww.flappybird"
DERIVED="${DERIVED:-build/DerivedData}"
SCREEN_ARGS="${SCREEN_ARGS:-}"

CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'; RESET='\033[0m'
info() { printf "${CYAN}▸ %s${RESET}\n" "$*"; }
ok()   { printf "${GREEN}✓ %s${RESET}\n" "$*"; }
fail() { printf "${RED}✖ %s${RESET}\n" "$*" >&2; exit 1; }

UDID="$(xcrun simctl list devices available \
        | grep -F "$SIMULATOR (" | head -1 \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || fail "Simulator '$SIMULATOR' not found (xcrun simctl list devices available)"

info "Building ${SCHEME}"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "id=$UDID" -configuration Debug \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null

APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/$SCHEME.app"
[ -d "$APP_PATH" ] || fail "Build product missing at $APP_PATH"

xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true
sleep 2

info "Installing"
xcrun simctl install "$UDID" "$APP_PATH"

info "Launching"
# shellcheck disable=SC2086
xcrun simctl launch "$UDID" "$BUNDLE_ID" $SCREEN_ARGS >/dev/null

ok "$SIMULATOR is running the game"
