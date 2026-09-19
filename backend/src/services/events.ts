/**
 * Tiny in-process pub/sub used by the Server-Sent Events endpoint.
 *
 * Scope is deliberately one process: a hobby deployment runs a single container,
 * and the game degrades gracefully to polling when the stream is unavailable.
 */
import { EventEmitter } from 'node:events';
import type { LeaderboardEntry } from '../domain/models.js';

export interface LeaderboardEvent {
  type: 'score.submitted' | 'leaderboard.changed' | 'heartbeat';
  at: string;
  payload?: {
    username?: string;
    score?: number;
    mode?: string;
    rank?: number | null;
    entry?: LeaderboardEntry;
  };
}

class EventHub extends EventEmitter {
  publish(event: LeaderboardEvent): void {
    this.emit('event', event);
  }

  subscribe(listener: (event: LeaderboardEvent) => void): () => void {
    this.on('event', listener);
    return () => this.off('event', listener);
  }
}

export const eventHub = new EventHub();
eventHub.setMaxListeners(0);
