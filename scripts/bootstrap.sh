#!/usr/bin/env bash
#
# One-time setup for contributors.
#
# Safe to re-run: every step is idempotent and each one is skipped with an
# explanation when its tool is not installed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CYAN='\033[1;36m'; GREEN='\033[1;32m'; DIM='\033[2m'; RESET='\033[0m'
step() { printf "${CYAN}▸ %s${RESET}\n" "$*"; }
ok()   { printf "${GREEN}✓ %s${RESET}\n" "$*"; }
skip() { printf "${DIM}  … %s${RESET}\n" "$*"; }

echo ""
step "Checking the toolchain"
bash scripts/doctor.sh || true

step "Installing git hooks"
mkdir -p .git/hooks
cat > .git/hooks/pre-commit <<'HOOK'
#!/usr/bin/env bash
# Keep the generated Xcode project in step with the files on disk.
set -e
if ! python3 scripts/generate_xcodeproj.py --check >/dev/null 2>&1; then
  echo "✖ The Xcode project is out of date. Run: make xcodegen"
  exit 1
fi
HOOK
chmod +x .git/hooks/pre-commit
ok "pre-commit hook installed"

step "Preparing the environment file"
if [ ! -f backend/.env ]; then
  cp backend/.env.example backend/.env
  ok "Created backend/.env from the example"
else
  skip "backend/.env already exists"
fi

step "Installing backend dependencies"
if command -v npm >/dev/null 2>&1; then
  (cd backend && npm install --no-audit --no-fund)
  ok "Backend dependencies installed"
else
  skip "npm not found — skipping (the game does not need it)"
fi

step "Regenerating the Xcode project"
python3 scripts/generate_xcodeproj.py
ok "Xcode project is up to date"

echo ""
ok "Bootstrap complete"
echo ""
echo -e "${DIM}  Play the game:      make run${RESET}"
echo -e "${DIM}  Start the backend:  make up${RESET}"
echo -e "${DIM}  See every target:   make${RESET}"
echo ""
