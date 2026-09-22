-- 004_score_sequence.sql — deterministic ordering for run history.
--
-- `submitted_at` has millisecond resolution, so two runs stored in the same
-- millisecond produced an arbitrary "newest first" order. A monotonic sequence
-- gives every run a stable tiebreaker without changing the public API.

ALTER TABLE scores ADD COLUMN IF NOT EXISTS seq BIGSERIAL;

CREATE INDEX IF NOT EXISTS scores_user_seq_idx ON scores (user_id, seq DESC);
