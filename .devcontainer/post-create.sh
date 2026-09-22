#!/usr/bin/env bash
#
# Runs once when the dev container is created.
set -euo pipefail

cd /workspace

echo "▸ Installing backend dependencies"
(cd backend && npm install --no-audit --no-fund)

echo "▸ Preparing backend/.env"
[ -f backend/.env ] || cp backend/.env.example backend/.env

echo "▸ Applying database migrations"
(cd backend && DB_DRIVER=postgres npm run migrate) || echo "  (database not ready yet — run 'make migrate' later)"

cat <<'BANNER'

  🐦  Dev container ready

  The iOS game needs macOS + Xcode and is not part of this container.
  Everything backend-related is:

    npm --prefix backend run dev     start the API with hot reload
    make api-test                    run the test suite
    make seed                        fill the database with demo players
    make openapi                     validate the OpenAPI document

  API:   http://localhost:4000
  Docs:  http://localhost:4000/docs

BANNER
