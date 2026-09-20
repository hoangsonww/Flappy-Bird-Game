# ─────────────────────────────────────────────────────────────────────────────
#  Flappy Bird — developer entry points
#
#  The game needs nothing but Xcode. Everything backend-related is optional and
#  lives behind the `up` / `dev` targets.
#
#      make            list every target
#      make doctor     check the toolchain
#      make run        build + launch the game in a simulator
#      make up         start Postgres + the API in Docker
# ─────────────────────────────────────────────────────────────────────────────

SHELL := /bin/bash
.DEFAULT_GOAL := help
.ONESHELL:

PROJECT       := Flappy Bird.xcodeproj
SCHEME        := FlappyBird
SIMULATOR     ?= iPhone 17 Pro
DESTINATION   := platform=iOS Simulator,name=$(SIMULATOR)
DERIVED       ?= build/DerivedData
CONFIGURATION ?= Debug
BUNDLE_ID     := com.hoangsonww.flappybird

BACKEND_DIR   := backend
COMPOSE       := docker compose
API_URL       ?= http://localhost:4000

CYAN  := \033[1;36m
GREEN := \033[1;32m
DIM   := \033[2m
RESET := \033[0m

.PHONY: help
help: ## Show this help
	@echo ""
	@echo -e "$(CYAN)Flappy Bird$(RESET) — make targets"
	@echo ""
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | sort \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1;32m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo -e "$(DIM)  The game runs with zero setup. Backend targets are optional.$(RESET)"
	@echo ""

# ── Environment ──────────────────────────────────────────────────────────────

.PHONY: doctor
doctor: ## Check that the required tools are installed
	@bash scripts/doctor.sh

.PHONY: bootstrap
bootstrap: ## One-time setup: install hooks and backend dependencies
	@bash scripts/bootstrap.sh

# ── iOS game ─────────────────────────────────────────────────────────────────

# Xcode keys the `.atlas` compile off the folder's timestamp, so editing a
# sprite in place leaves a stale `bird.atlasc` in the app bundle and the game
# keeps drawing the old art with no warning. Touching the folder is free.
.PHONY: touch-atlases
touch-atlases:
	@touch FlappyBird/*.atlas

.PHONY: build
build: touch-atlases ## Build the game for the simulator
	@echo -e "$(CYAN)▸ Building $(SCHEME) ($(CONFIGURATION))$(RESET)"
	@xcodebuild -project "$(PROJECT)" -scheme $(SCHEME) \
	  -destination "$(DESTINATION)" -configuration $(CONFIGURATION) \
	  -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO build | \
	  grep -E "error:|warning:|BUILD" || true

.PHONY: test
test: touch-atlases ## Run the Swift unit tests
	@echo -e "$(CYAN)▸ Testing $(SCHEME) (unit)$(RESET)"
	@xcodebuild -project "$(PROJECT)" -scheme $(SCHEME) \
	  -destination "$(DESTINATION)" -configuration Debug \
	  -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO \
	  -only-testing:FlappyBirdTests test | \
	  grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" || true

# Drives the real UI on a simulator, so it is minutes rather than seconds —
# kept out of `make test` and run on its own or via `make test-all`.
.PHONY: test-ui
test-ui: touch-atlases ## Run the XCUITest suite against a simulator
	@echo -e "$(CYAN)▸ Testing $(SCHEME) (UI)$(RESET)"
	@xcodebuild -project "$(PROJECT)" -scheme $(SCHEME) \
	  -destination "$(DESTINATION)" -configuration Debug \
	  -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO \
	  -only-testing:FlappyBirdUITests test | \
	  grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" || true

.PHONY: test-all
test-all: touch-atlases ## Run both the unit and the UI suites
	@echo -e "$(CYAN)▸ Testing $(SCHEME) (unit + UI)$(RESET)"
	@xcodebuild -project "$(PROJECT)" -scheme $(SCHEME) \
	  -destination "$(DESTINATION)" -configuration Debug \
	  -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO test | \
	  grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" || true

.PHONY: run
run: build ## Build, install and launch the game in the simulator
	@bash scripts/run-simulator.sh

.PHONY: demo
demo: ## Launch the game in self-playing attract mode
	@SCREEN_ARGS="-seed-demo -demo" bash scripts/run-simulator.sh

.PHONY: media
media: ## Capture every screenshot from the simulator
	@bash scripts/capture-media.sh

.PHONY: xcodegen
xcodegen: ## Regenerate the Xcode project from the files on disk
	@python3 scripts/generate_xcodeproj.py

.PHONY: xcodegen-check
xcodegen-check: ## Fail if the checked-in Xcode project is stale
	@python3 scripts/generate_xcodeproj.py --check

.PHONY: lint-swift
lint-swift: ## Run SwiftLint when it is installed
	@if command -v swiftlint >/dev/null; then \
	  swiftlint lint --quiet; \
	else \
	  echo "swiftlint not installed — skipping (brew install swiftlint)"; \
	fi

.PHONY: format-swift
format-swift: ## Run SwiftFormat when it is installed
	@if command -v swiftformat >/dev/null; then \
	  swiftformat . ; \
	else \
	  echo "swiftformat not installed — skipping (brew install swiftformat)"; \
	fi

# ── Backend (optional) ───────────────────────────────────────────────────────

.PHONY: install
install: ## Install backend dependencies
	@cd $(BACKEND_DIR) && npm install

.PHONY: dev
dev: ## Run the backend locally with hot reload (in-memory storage)
	@cd $(BACKEND_DIR) && npm run dev

.PHONY: api-test
api-test: ## Run the backend test suite (in-memory driver)
	@cd $(BACKEND_DIR) && npm test

.PHONY: api-test-pg
api-test-pg: up-db ## Run the backend test suite against Postgres
	@cd $(BACKEND_DIR) && DB_DRIVER=postgres npm test

.PHONY: api-coverage
api-coverage: ## Backend tests with a coverage report
	@cd $(BACKEND_DIR) && npm run test:coverage

.PHONY: api-lint
api-lint: ## Lint and type-check the backend
	@cd $(BACKEND_DIR) && npm run lint && npm run typecheck

.PHONY: api-format
api-format: ## Format the backend sources
	@cd $(BACKEND_DIR) && npm run format

.PHONY: openapi
openapi: ## Validate the OpenAPI specification
	@cd $(BACKEND_DIR) && npm run openapi:validate

.PHONY: docs-api
docs-api: ## Open the Swagger UI (backend must be running)
	@open $(API_URL)/docs || echo "Visit $(API_URL)/docs"

# ── Docker ───────────────────────────────────────────────────────────────────

.PHONY: up
up: ## Start Postgres + the API in Docker
	@$(COMPOSE) up -d --build postgres backend
	@bash scripts/wait-for-health.sh $(API_URL)/healthz
	@echo -e "$(GREEN)✓ API ready at $(API_URL) — docs at $(API_URL)/docs$(RESET)"

.PHONY: up-db
up-db: ## Start only Postgres
	@$(COMPOSE) up -d postgres
	@$(COMPOSE) exec -T postgres sh -c 'until pg_isready -U flappy -d flappybird; do sleep 1; done'

.PHONY: up-tools
up-tools: up ## Start the stack plus the pgweb database browser
	@$(COMPOSE) --profile tools up -d pgweb
	@echo -e "$(GREEN)✓ pgweb at http://localhost:8081$(RESET)"

.PHONY: up-observability
up-observability: up ## Start the stack plus Prometheus and Grafana
	@$(COMPOSE) --profile observability up -d prometheus grafana
	@echo -e "$(GREEN)✓ Prometheus http://localhost:9090 · Grafana http://localhost:3001$(RESET)"

.PHONY: down
down: ## Stop every container
	@$(COMPOSE) --profile tools --profile observability down

.PHONY: clean-volumes
clean-volumes: ## Stop everything and delete the database volume
	@$(COMPOSE) --profile tools --profile observability down -v

.PHONY: logs
logs: ## Tail the backend logs
	@$(COMPOSE) logs -f backend

.PHONY: ps
ps: ## Show container status
	@$(COMPOSE) ps

.PHONY: psql
psql: ## Open a psql shell against the dev database
	@$(COMPOSE) exec postgres psql -U flappy -d flappybird

.PHONY: migrate
migrate: ## Apply pending database migrations
	@cd $(BACKEND_DIR) && DB_DRIVER=postgres npm run migrate

.PHONY: migrate-status
migrate-status: ## Show which migrations have been applied
	@cd $(BACKEND_DIR) && DB_DRIVER=postgres npm run migrate:status

.PHONY: seed
seed: ## Fill the database with demo players and runs
	@cd $(BACKEND_DIR) && DB_DRIVER=postgres npm run seed

.PHONY: smoke
smoke: ## End-to-end smoke test against a running API
	@cd $(BACKEND_DIR) && BASE_URL=$(API_URL) npm run smoke

.PHONY: health
health: ## Print the API health document
	@curl -fsS $(API_URL)/healthz | python3 -m json.tool || echo "API is not running — try: make up"

# ── Quality gates ────────────────────────────────────────────────────────────

.PHONY: check
check: xcodegen-check api-lint openapi api-test ## Everything CI runs, except the iOS build
	@echo -e "$(GREEN)✓ All checks passed$(RESET)"

.PHONY: ci
ci: check build test ## Full local equivalent of the CI pipeline
	@echo -e "$(GREEN)✓ CI-equivalent run complete$(RESET)"

.PHONY: clean
clean: ## Remove build output and caches
	@rm -rf build $(BACKEND_DIR)/dist $(BACKEND_DIR)/coverage
	@xcodebuild -project "$(PROJECT)" -scheme $(SCHEME) clean >/dev/null 2>&1 || true
	@echo -e "$(GREEN)✓ Cleaned$(RESET)"
