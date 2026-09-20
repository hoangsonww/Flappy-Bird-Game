-- Drop the Ghost Rider achievement.
--
-- The ghost replay it rewarded has been removed from the game: a translucent
-- second bird flying the player's best run read as a rendering fault rather
-- than as a feature, and replaying a recorded run belongs in a mode of its own
-- rather than bolted into the live scene.
--
-- `user_achievements.code` references this row with ON DELETE CASCADE, so any
-- unlocks players already earned go with it.

DELETE FROM achievements WHERE code = 'ghost_rider';
