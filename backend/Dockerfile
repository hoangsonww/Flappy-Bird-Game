# syntax=docker/dockerfile:1.7
# ──────────────────────────────────────────────────────────────────────────────
# Flappy Bird backend — multi-stage build.
#
#   deps   installs every dependency (needs dev deps to compile TypeScript)
#   build  type-checks and emits dist/
#   prod   copies dist/ + production node_modules onto a slim, non-root runtime
#
# Build:  docker build -t flappy-bird-backend ./backend
# Run:    docker run --rm -p 4000:4000 -e DB_DRIVER=memory flappy-bird-backend
# ──────────────────────────────────────────────────────────────────────────────
ARG NODE_VERSION=22

# ── deps ─────────────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm \
    if [ -f package-lock.json ]; then npm ci; else npm install; fi

# ── build ────────────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run typecheck && npm run build

# ── production dependencies only ─────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS prod-deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm \
    if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

# ── runtime ──────────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS prod

# dumb-init gives us correct signal forwarding so SIGTERM reaches Node directly.
RUN apk add --no-cache dumb-init curl \
    && addgroup -g 1001 -S flappy \
    && adduser -S flappy -u 1001 -G flappy

WORKDIR /app
ENV NODE_ENV=production \
    PORT=4000 \
    HOST=0.0.0.0 \
    NODE_OPTIONS=--enable-source-maps

COPY --from=prod-deps --chown=flappy:flappy /app/node_modules ./node_modules
COPY --from=build     --chown=flappy:flappy /app/dist          ./dist
COPY --chown=flappy:flappy package.json ./
COPY --chown=flappy:flappy migrations ./migrations
COPY --chown=flappy:flappy openapi ./openapi

USER flappy
EXPOSE 4000

HEALTHCHECK --interval=15s --timeout=4s --start-period=20s --retries=5 \
    CMD curl -fsS "http://127.0.0.1:${PORT}/healthz" > /dev/null || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/server.js"]

LABEL org.opencontainers.image.title="Flappy Bird Backend" \
      org.opencontainers.image.description="Optional accounts, leaderboards and score sync for the Flappy Bird iOS game." \
      org.opencontainers.image.source="https://github.com/hoangsonww/Flappy-Bird-Game" \
      org.opencontainers.image.licenses="MIT"
