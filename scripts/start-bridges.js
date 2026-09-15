/**
 * start-bridges.js — standalone entrypoint to start pg-bridge and redis-bridge.
 *
 * Usage:
 *   node scripts/start-bridges.js
 *
 * Spawns both bridges as child processes and waits for their /health
 * endpoints before exiting. Designed to be called from npm scripts,
 * Docker entrypoints, or any Node.js process that needs bridges running.
 */

import { spawn } from 'child_process';
import path from 'path';
import http from 'http';

const PG_PORT = 8080;
const REDIS_PORT = 8081;

function checkHealth(port, cb) {
  const req = http.get(`http://127.0.0.1:${port}/health`, (res) => {
    cb(res.statusCode === 200);
  });
  req.on('error', () => {
    cb(false);
  });
  req.setTimeout(500, () => {
    req.destroy();
    cb(false);
  });
}

function checkHealthAsync(port) {
  return new Promise((resolve) => {
    checkHealth(port, resolve);
  });
}

async function waitForHealth(port, maxRetries, intervalMs) {
  maxRetries = maxRetries || 20;
  intervalMs = intervalMs || 500;
  let retries = 0;
  while (retries < maxRetries) {
    const alive = await checkHealthAsync(port);
    if (alive) return;
    retries++;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  throw new Error(`Bridge on port ${port} failed to become healthy after ${maxRetries} retries`);
}

async function startBridges() {
  // Start pg-bridge if not already running
  const pgAlive = await checkHealthAsync(PG_PORT);
  if (!pgAlive) {
    console.log('[start-bridges] Starting pg-bridge...');
    const pg = spawn('python3', [path.resolve(process.cwd(), 'srv/pg-bridge/main.py')], {
      env: {
        ...process.env,
        PG_BRIDGE_HOST: '127.0.0.1',
        PG_BRIDGE_PORT: String(PG_PORT),
        PG_BACKEND: process.env.PG_BACKEND || 'sqlite',
      },
      stdio: 'inherit',
      detached: true,
    });
    pg.unref();
  } else {
    console.log('[start-bridges] pg-bridge already running on port', PG_PORT);
  }

  // Start redis-bridge if not already running
  const redisAlive = await checkHealthAsync(REDIS_PORT);
  if (!redisAlive) {
    console.log('[start-bridges] Starting redis-bridge...');
    const redis = spawn('python3', [path.resolve(process.cwd(), 'srv/redis-bridge/main.py')], {
      env: {
        ...process.env,
        REDIS_BRIDGE_HOST: '127.0.0.1',
        REDIS_BRIDGE_PORT: String(REDIS_PORT),
        REDIS_BACKEND: process.env.REDIS_BACKEND || 'inmemory',
      },
      stdio: 'inherit',
      detached: true,
    });
    redis.unref();
  } else {
    console.log('[start-bridges] redis-bridge already running on port', REDIS_PORT);
  }

  // Wait for both to be healthy
  console.log('[start-bridges] Waiting for pg-bridge health...');
  await waitForHealth(PG_PORT);
  console.log('[start-bridges] pg-bridge healthy');

  console.log('[start-bridges] Waiting for redis-bridge health...');
  await waitForHealth(REDIS_PORT);
  console.log('[start-bridges] redis-bridge healthy');

  console.log('[start-bridges] Both bridges are running');
}

startBridges().catch((err) => {
  console.error('[start-bridges] Failed to start bridges:', err);
  process.exit(1);
});