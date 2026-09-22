-- 002_achievements_seed.sql — the achievement catalog is reference data, so it
-- ships as a migration. Re-running is safe: definitions are upserted by code.

INSERT INTO achievements (code, name, description, icon, points, metric, threshold, secret) VALUES
    ('first_flight',  'First Flight',  'Pass your first pipe.',                      '🐣', 5,   'score',   1,    FALSE),
    ('getting_warm',  'Getting Warm',  'Score 10 in a single run.',                  '🔥', 10,  'score',   10,   FALSE),
    ('sky_rookie',    'Sky Rookie',    'Score 25 in a single run.',                  '🪶', 20,  'score',   25,   FALSE),
    ('pipe_dreamer',  'Pipe Dreamer',  'Score 50 in a single run.',                  '🌤️', 40,  'score',   50,   FALSE),
    ('century',       'Century Club',  'Score 100 in a single run.',                 '💯', 100, 'score',   100,  FALSE),
    ('legend',        'Living Legend', 'Score 200 in a single run.',                 '👑', 250, 'score',   200,  FALSE),
    ('coin_collector','Coin Collector','Collect 100 coins in total.',                '🪙', 15,  'coins',   100,  FALSE),
    ('treasury',      'Treasury',      'Collect 1,000 coins in total.',              '💰', 60,  'coins',   1000, FALSE),
    ('persistent',    'Persistent',    'Play 50 games.',                             '🎮', 20,  'games',   50,   FALSE),
    ('dedicated',     'Dedicated',     'Play 250 games.',                            '🏅', 75,  'games',   250,  FALSE),
    ('pipe_marathon', 'Pipe Marathon', 'Pass 1,000 pipes in total.',                 '🏃', 50,  'pipes',   1000, FALSE),
    ('combo_artist',  'Combo Artist',  'Reach a x10 combo.',                         '✨', 35,  'combo',   10,   FALSE),
    ('untouchable',   'Untouchable',   'Reach a x25 combo.',                         '⚡', 90,  'combo',   25,   FALSE),
    ('night_owl',     'Night Owl',     'Finish a run during the night cycle.',       '🌙', 15,  'special', 1,    FALSE),
    ('storm_chaser',  'Storm Chaser',  'Survive 30 seconds of wind.',                '🌪️', 30,  'special', 1,    FALSE),
    ('daily_devotee', 'Daily Devotee', 'Complete 7 daily challenges.',               '📅', 70,  'special', 7,    FALSE),
    ('perfect_start', 'Perfect Start', 'Pass 10 pipes without using a power-up.',    '🎯', 25,  'special', 1,    FALSE),
    ('ghost_rider',   'Ghost Rider',   'Beat your own ghost replay.',                '👻', 45,  'special', 1,    TRUE)
ON CONFLICT (code) DO UPDATE SET
    name        = EXCLUDED.name,
    description = EXCLUDED.description,
    icon        = EXCLUDED.icon,
    points      = EXCLUDED.points,
    metric      = EXCLUDED.metric,
    threshold   = EXCLUDED.threshold,
    secret      = EXCLUDED.secret;
