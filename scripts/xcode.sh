#!/usr/bin/env bash
#
# Run xcodebuild for the game and *keep its exit status*.
#
#   scripts/xcode.sh build
#   scripts/xcode.sh test FlappyBirdTests
#   scripts/xcode.sh test FlappyBirdUITests
#   scripts/xcode.sh test all
#
# The Makefile used to pipe xcodebuild into `grep … || true`, which made every
# target exit 0 — a missing simulator, a compile error and a failing assertion
# all looked identical to a green run. The output is still filtered, but the
# status now comes from xcodebuild and the tail of the real log is printed when
# something goes wrong.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ACTION="${1:-build}"
ONLY="${2:-}"

PROJECT="Flappy Bird.xcodeproj"
SCHEME="FlappyBird"
DERIVED="${DERIVED:-build/DerivedData}"
CONFIGURATION="${CONFIGURATION:-Debug}"

RED='\033[1;31m'; DIM='\033[2m'; RESET='\033[0m'

UDID="$(bash scripts/simulator-udid.sh)"

args=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "id=$UDID"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED"
  CODE_SIGNING_ALLOWED=NO
)

case "$ACTION" in
  build) args+=(build) ;;
  test)
    [ -n "$ONLY" ] && [ "$ONLY" != "all" ] && args+=(-only-testing:"$ONLY")
    args+=(test)
    ;;
  *)
    echo "usage: scripts/xcode.sh {build|test} [target]" >&2
    exit 64
    ;;
esac

log="$(mktemp -t flappy-xcodebuild)"
trap 'rm -f "$log"' EXIT

printf "${DIM}simulator %s${RESET}\n" "$UDID"

status=0
xcodebuild "${args[@]}" > "$log" 2>&1 || status=$?

grep -E "error:|warning: .*(deprecated|unused)|Executed [0-9]+ tests|(TEST|BUILD) (SUCCEEDED|FAILED)" "$log" \
  | grep -vE "platform doesn.t match|Base SDK or Supported Platforms" \
  || true

if [ "$status" -ne 0 ]; then
  printf "${RED}✖ xcodebuild exited %s${RESET}\n" "$status" >&2
  echo "── last 40 lines ─────────────────────────────────────────────" >&2
  tail -40 "$log" >&2
fi

exit "$status"
