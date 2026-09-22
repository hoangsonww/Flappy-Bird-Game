-- 001_init.sql — core schema for accounts, runs, leaderboards and achievements.
-- Every timestamp is stored as timestamptz (UTC). Identifiers are UUIDs generated
-- by the application so the same code path works for both storage drivers.

CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY,
    username        TEXT        NOT NULL,
    username_lower  TEXT        NOT NULL,
    email           TEXT,
    email_lower     TEXT,
    password_hash   TEXT,
    display_name    TEXT        NOT NULL,
    country         TEXT,
    avatar_skin     TEXT        NOT NULL DEFAULT 'classic',
    role            TEXT        NOT NULL DEFAULT 'player',
    is_guest        BOOLEAN     NOT NULL DEFAULT FALSE,
    device_id       TEXT,
    is_banned       BOOLEAN     NOT NULL DEFAULT FALSE,
    ban_reason      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_role_check CHECK (role IN ('player', 'admin')),
    CONSTRAINT users_username_length CHECK (char_length(username) BETWEEN 3 AND 20)
);

CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_key ON users (username_lower);
CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_key ON users (email_lower) WHERE email_lower IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS users_device_id_key ON users (device_id) WHERE device_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id          UUID PRIMARY KEY,
    user_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    user_agent  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS refresh_tokens_hash_key ON refresh_tokens (token_hash);
CREATE INDEX IF NOT EXISTS refresh_tokens_user_idx ON refresh_tokens (user_id, revoked_at);
CREATE INDEX IF NOT EXISTS refresh_tokens_expiry_idx ON refresh_tokens (expires_at);

CREATE TABLE IF NOT EXISTS scores (
    id              UUID PRIMARY KEY,
    user_id         UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    score           INTEGER     NOT NULL CHECK (score >= 0),
    mode            TEXT        NOT NULL,
    coins           INTEGER     NOT NULL DEFAULT 0 CHECK (coins >= 0),
    pipes_passed    INTEGER     NOT NULL DEFAULT 0 CHECK (pipes_passed >= 0),
    duration_ms     INTEGER     NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
    max_combo       INTEGER     NOT NULL DEFAULT 0 CHECK (max_combo >= 0),
    power_ups_used  INTEGER     NOT NULL DEFAULT 0 CHECK (power_ups_used >= 0),
    seed            TEXT        NOT NULL DEFAULT '',
    client_version  TEXT,
    device_model    TEXT,
    flagged         BOOLEAN     NOT NULL DEFAULT FALSE,
    flag_reason     TEXT,
    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT scores_mode_check CHECK (mode IN ('classic', 'endless', 'timeAttack', 'hardcore', 'zen', 'daily'))
);

-- Leaderboard hot path: "best score per user in a window, optionally per mode".
CREATE INDEX IF NOT EXISTS scores_board_idx ON scores (mode, submitted_at DESC, score DESC) WHERE flagged = FALSE;
CREATE INDEX IF NOT EXISTS scores_user_recent_idx ON scores (user_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS scores_user_best_idx ON scores (user_id, score DESC) WHERE flagged = FALSE;

CREATE TABLE IF NOT EXISTS user_stats (
    user_id           UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    best_score        INTEGER     NOT NULL DEFAULT 0,
    best_score_mode   TEXT,
    total_score       BIGINT      NOT NULL DEFAULT 0,
    games_played      INTEGER     NOT NULL DEFAULT 0,
    total_coins       BIGINT      NOT NULL DEFAULT 0,
    total_pipes       BIGINT      NOT NULL DEFAULT 0,
    total_duration_ms BIGINT      NOT NULL DEFAULT 0,
    longest_run_ms    INTEGER     NOT NULL DEFAULT 0,
    best_combo        INTEGER     NOT NULL DEFAULT 0,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_stats_best_idx ON user_stats (best_score DESC);

CREATE TABLE IF NOT EXISTS achievements (
    code        TEXT PRIMARY KEY,
    name        TEXT    NOT NULL,
    description TEXT    NOT NULL,
    icon        TEXT    NOT NULL DEFAULT '🏆',
    points      INTEGER NOT NULL DEFAULT 0,
    metric      TEXT    NOT NULL DEFAULT 'special',
    threshold   INTEGER NOT NULL DEFAULT 1,
    secret      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS user_achievements (
    user_id     UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    code        TEXT NOT NULL REFERENCES achievements (code) ON DELETE CASCADE,
    progress    INTEGER     NOT NULL DEFAULT 0,
    unlocked_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, code)
);

CREATE INDEX IF NOT EXISTS user_achievements_unlocked_idx ON user_achievements (user_id, unlocked_at);

CREATE TABLE IF NOT EXISTS friendships (
    user_id    UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    friend_id  UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    status     TEXT        NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, friend_id),
    CONSTRAINT friendships_no_self CHECK (user_id <> friend_id)
);

CREATE TABLE IF NOT EXISTS daily_challenges (
    date          DATE PRIMARY KEY,
    seed          TEXT        NOT NULL,
    mode          TEXT        NOT NULL,
    pipe_gap      INTEGER     NOT NULL,
    gravity_scale NUMERIC(4, 2) NOT NULL,
    speed_scale   NUMERIC(4, 2) NOT NULL,
    modifier      TEXT        NOT NULL DEFAULT 'none',
    description   TEXT        NOT NULL DEFAULT '',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS challenge_entries (
    date         DATE        NOT NULL REFERENCES daily_challenges (date) ON DELETE CASCADE,
    user_id      UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    score        INTEGER     NOT NULL CHECK (score >= 0),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (date, user_id)
);

CREATE INDEX IF NOT EXISTS challenge_entries_board_idx ON challenge_entries (date, score DESC, submitted_at ASC);
