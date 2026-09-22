-- 003_leaderboard_view.sql — convenience view used by ad-hoc analytics and the
-- admin dashboard. The API itself ranks with an explicit CTE so it can filter by
-- time window without invalidating the view.

CREATE OR REPLACE VIEW leaderboard_all_time AS
WITH best AS (
    SELECT DISTINCT ON (s.user_id)
        s.user_id,
        s.id AS score_id,
        s.score,
        s.mode,
        s.coins,
        s.pipes_passed,
        s.duration_ms,
        s.submitted_at
    FROM scores s
    JOIN users u ON u.id = s.user_id
    WHERE s.flagged = FALSE AND u.is_banned = FALSE
    ORDER BY s.user_id, s.score DESC, s.submitted_at ASC
)
SELECT
    RANK() OVER (ORDER BY b.score DESC, b.submitted_at ASC) AS rank,
    b.score_id,
    b.user_id,
    u.username,
    u.display_name,
    u.avatar_skin,
    u.country,
    b.score,
    b.mode,
    b.coins,
    b.pipes_passed,
    b.duration_ms,
    b.submitted_at AS achieved_at
FROM best b
JOIN users u ON u.id = b.user_id;
