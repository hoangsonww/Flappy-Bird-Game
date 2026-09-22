#!/usr/bin/env bash
#
# Report which tools are present and what each one unlocks.
#
# Only Xcode is required — everything else is optional, and the script says so
# rather than failing, because the game itself has no other dependencies.
set -uo pipefail

CYAN='\033[1;36m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; DIM='\033[2m'; RESET='\033[0m'

required_missing=0

check() {
  local name="$1" command_name="$2" requirement="$3" purpose="$4" install_hint="$5"
  local version=""

  if command -v "$command_name" >/dev/null 2>&1; then
    case "$command_name" in
      xcodebuild) version="$(xcodebuild -version 2>/dev/null | head -1)" ;;
      node)       version="node $(node -v 2>/dev/null)" ;;
      npm)        version="npm $(npm -v 2>/dev/null)" ;;
      docker)     version="$(docker --version 2>/dev/null | cut -d, -f1)" ;;
      python3)    version="$(python3 -V 2>&1)" ;;
      *)          version="$($command_name --version 2>/dev/null | head -1)" ;;
    esac
    printf "  ${GREEN}✓${RESET} %-14s ${DIM}%s${RESET}\n" "$name" "${version:-found}"
  elif [ "$requirement" = "required" ]; then
    printf "  ${RED}✖${RESET} %-14s %s\n" "$name" "$purpose"
    printf "     ${DIM}install: %s${RESET}\n" "$install_hint"
    required_missing=$((required_missing + 1))
  else
    printf "  ${YELLOW}○${RESET} %-14s ${DIM}optional — %s${RESET}\n" "$name" "$purpose"
    printf "     ${DIM}install: %s${RESET}\n" "$install_hint"
  fi
}

echo ""
echo -e "${CYAN}Flappy Bird — environment check${RESET}"
echo ""
echo -e "${DIM}Required to play the game${RESET}"
check "Xcode"      xcodebuild required "builds and runs the iOS game"        "https://apps.apple.com/app/xcode/id497799835"
check "Python 3"   python3    required "regenerates the Xcode project"       "ships with macOS, or: brew install python"

echo ""
echo -e "${DIM}Required only for the optional backend${RESET}"
check "Node.js 20+" node      optional "runs the API without Docker"          "brew install node"
check "npm"         npm       optional "installs backend dependencies"        "ships with Node.js"
check "Docker"      docker    optional "runs Postgres + the API in one command" "https://docs.docker.com/get-docker/"

echo ""
echo -e "${DIM}Nice to have${RESET}"
check "SwiftLint"   swiftlint optional "lints the Swift sources"              "brew install swiftlint"
check "SwiftFormat" swiftformat optional "formats the Swift sources"          "brew install swiftformat"
check "gh"          gh        optional "opens pull requests from the terminal" "brew install gh"

# ── Simulators ───────────────────────────────────────────────────────────────
echo ""
if command -v xcrun >/dev/null 2>&1; then
  simulator_count="$(xcrun simctl list devices available 2>/dev/null | grep -c "iPhone" || true)"
  if [ "${simulator_count:-0}" -gt 0 ]; then
    printf "  ${GREEN}✓${RESET} %-14s ${DIM}%s iPhone simulator(s) available${RESET}\n" "Simulators" "$simulator_count"
  else
    printf "  ${YELLOW}○${RESET} %-14s ${DIM}no iPhone simulators installed — open Xcode ▸ Settings ▸ Components${RESET}\n" "Simulators"
  fi
fi

# ── Backend reachability ────────────────────────────────────────────────────
if curl -fsS --max-time 2 http://localhost:4000/healthz >/dev/null 2>&1; then
  printf "  ${GREEN}✓${RESET} %-14s ${DIM}backend is running at http://localhost:4000${RESET}\n" "Backend"
else
  printf "  ${DIM}  ○ Backend        not running (entirely optional — 'make up' starts it)${RESET}\n"
fi

echo ""
if [ "$required_missing" -gt 0 ]; then
  echo -e "${RED}✖ $required_missing required tool(s) missing.${RESET}"
  exit 1
fi
echo -e "${GREEN}✓ You can build and play the game.${RESET}"
echo -e "${DIM}  Next: make run${RESET}"
echo ""
