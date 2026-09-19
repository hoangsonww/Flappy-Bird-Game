import { z } from 'zod';
import { env } from '../config/env.js';
import { badRequest } from './errors.js';

export const paginationSchema = z.object({
  limit: z.coerce.number().int().min(1).max(env.LEADERBOARD_PAGE_MAX).default(25),
  offset: z.coerce.number().int().min(0).max(100_000).default(0),
});

export type Pagination = z.infer<typeof paginationSchema>;

export interface Page<T> {
  items: T[];
  total: number;
  limit: number;
  offset: number;
  hasMore: boolean;
}

export function page<T>(items: T[], total: number, pagination: Pagination): Page<T> {
  return {
    items,
    total,
    limit: pagination.limit,
    offset: pagination.offset,
    hasMore: pagination.offset + items.length < total,
  };
}

/** Opaque cursor helpers for score history (`submitted_at` + `id` keyset). */
export function encodeCursor(payload: Record<string, string | number>): string {
  return Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
}

export function decodeCursor<T = Record<string, string | number>>(cursor: string): T {
  try {
    return JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as T;
  } catch {
    throw badRequest('Malformed cursor');
  }
}
