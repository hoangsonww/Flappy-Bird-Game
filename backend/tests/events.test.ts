import { once } from 'node:events';
import type { AddressInfo } from 'node:net';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { Server } from 'node:http';
import { eventHub } from '../src/services/events.js';
import { freshApp } from './helpers.js';

describe('leaderboard events', () => {
  let server: Server | undefined;

  beforeEach(async () => {
    await freshApp();
  });

  afterEach(async () => {
    if (!server) return;
    server.closeAllConnections();
    server.close();
    server = undefined;
  });

  it('subscribes, publishes, and unsubscribes listeners', () => {
    const received: string[] = [];
    const unsubscribe = eventHub.subscribe((event) => received.push(event.type));
    eventHub.publish({ type: 'leaderboard.changed', at: '2026-01-01T00:00:00.000Z' });
    unsubscribe();
    eventHub.publish({ type: 'heartbeat', at: '2026-01-01T00:00:01.000Z' });
    expect(received).toEqual(['leaderboard.changed']);
  });

  it('streams the connection event and subsequent updates over SSE', async () => {
    const app = await freshApp();
    server = app.listen(0);
    await once(server, 'listening');
    const port = (server.address() as AddressInfo).port;
    const controller = new AbortController();
    const response = await fetch(`http://127.0.0.1:${port}/v1/leaderboard/stream`, {
      signal: controller.signal,
    });
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('text/event-stream');

    const reader = response.body!.getReader();
    const decoder = new TextDecoder();
    let content = decoder.decode((await reader.read()).value, { stream: true });
    expect(content).toContain('event: connected');

    eventHub.publish({
      type: 'score.submitted',
      at: '2026-01-01T00:00:00.000Z',
      payload: { username: 'stream_bird', score: 42, mode: 'classic', rank: 1 },
    });
    while (!content.includes('score.submitted')) {
      const chunk = await reader.read();
      if (chunk.done) break;
      content += decoder.decode(chunk.value, { stream: true });
    }

    expect(content).toContain('event: score.submitted');
    expect(content).toContain('"username":"stream_bird"');
    controller.abort();
  });
});
