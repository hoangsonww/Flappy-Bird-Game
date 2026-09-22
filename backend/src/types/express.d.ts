import type { User } from '../domain/models.js';

declare global {
  namespace Express {
    interface Request {
      /** Correlation id echoed back as the `X-Request-Id` response header. */
      requestId: string;
      /** Present once `requireAuth` / `optionalAuth` has run successfully. */
      user?: User;
    }
  }
}

export {};
