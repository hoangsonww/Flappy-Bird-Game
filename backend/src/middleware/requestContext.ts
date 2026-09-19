import type { NextFunction, Request, Response } from 'express';
import { randomUUID } from 'node:crypto';

/**
 * Attach a correlation id to every request.
 * Honours an inbound `X-Request-Id` so a client can trace its own calls.
 */
export function requestContext(req: Request, res: Response, next: NextFunction): void {
  const inbound = req.header('x-request-id');
  req.requestId = inbound && inbound.length <= 128 ? inbound : randomUUID();
  res.setHeader('X-Request-Id', req.requestId);
  next();
}
