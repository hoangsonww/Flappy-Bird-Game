/** Mounts every versioned router under `/v1`. */
import { Router } from 'express';
import { globalLimiter } from '../middleware/rateLimit.js';
import { achievementsRouter } from './achievements.js';
import { adminRouter } from './admin.js';
import { authRouter } from './auth.js';
import { challengesRouter } from './challenges.js';
import { friendsRouter } from './friends.js';
import { leaderboardRouter } from './leaderboard.js';
import { metaRouter } from './meta.js';
import { scoresRouter } from './scores.js';
import { usersRouter } from './users.js';

export const v1Router = Router();

v1Router.use(globalLimiter);
v1Router.use('/meta', metaRouter);
v1Router.use('/auth', authRouter);
v1Router.use('/users', usersRouter);
v1Router.use('/scores', scoresRouter);
v1Router.use('/leaderboard', leaderboardRouter);
v1Router.use('/achievements', achievementsRouter);
v1Router.use('/challenges', challengesRouter);
v1Router.use('/friends', friendsRouter);
v1Router.use('/admin', adminRouter);
