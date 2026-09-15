import { spawn, ChildProcess } from 'child_process';
import path from 'path';
import http from 'http';

let pgProcess: ChildProcess | null = null;
let redisProcess: ChildProcess | null = null;

const PG_PORT = 8080;
const REDIS_PORT = 8081;

export function ensureBridgesRunning(): Promise<{ pgPort: number; redisPort: number }> {
  return new Promise((resolve) => {
    // Check if bridges are already alive
    checkHealth(PG_PORT, (pgAlive) => {
      if (!pgAlive && !pgProcess) {
        pgProcess = spawn('python3', [path.resolve(process.cwd(), 'srv/pg-bridge/main.py')], {
          env: {
            ...process.env,
            PG_BRIDGE_HOST: '127.0.0.1',
            PG_BRIDGE_PORT: String(PG_PORT),
            PG_BACKEND: process.env.PG_BACKEND || 'sqlite',
          },
          stdio: 'inherit',
        });
        pgProcess.on('error', (err) => {
          console.warn('[bridge_manager] pgProcess error:', err.message);
        });
      }

      checkHealth(REDIS_PORT, (redisAlive) => {
        if (!redisAlive && !redisProcess) {
          redisProcess = spawn('python3', [path.resolve(process.cwd(), 'srv/redis-bridge/main.py')], {
            env: {
              ...process.env,
              REDIS_BRIDGE_HOST: '127.0.0.1',
              REDIS_BRIDGE_PORT: String(REDIS_PORT),
              REDIS_BACKEND: process.env.REDIS_BACKEND || 'inmemory',
            },
            stdio: 'inherit',
          });
          redisProcess.on('error', (err) => {
            console.warn('[bridge_manager] redisProcess error:', err.message);
          });
        }

        // Wait a short tick for boot if either was newly spawned
        setTimeout(() => {
          resolve({ pgPort: PG_PORT, redisPort: REDIS_PORT });
        }, 300);
      });
    });
  });
}

/**
 * Standalone function to start bridges and wait for both to become healthy.
 * Can be called from any entrypoint (Node.js script, Docker container, etc.).
 * Spawns the bridges as child processes and resolves only after both
 * report healthy on their respective /health endpoints.
 */
export async function startBridges(): Promise<void> {
  // Start pg-bridge if not already running
  const pgAlive = await checkHealthAsync(PG_PORT);
  if (!pgAlive) {
    pgProcess = spawn('python3', [path.resolve(process.cwd(), 'srv/pg-bridge/main.py')], {
      env: {
        ...process.env,
        PG_BRIDGE_HOST: '127.0.0.1',
        PG_BRIDGE_PORT: String(PG_PORT),
        PG_BACKEND: process.env.PG_BACKEND || 'sqlite',
      },
      stdio: 'inherit',
    });
    pgProcess.on('error', (err) => {
      console.warn('[bridge_manager] pgProcess error:', err.message);
    });
  }

  // Start redis-bridge if not already running
  const redisAlive = await checkHealthAsync(REDIS_PORT);
  if (!redisAlive) {
    redisProcess = spawn('python3', [path.resolve(process.cwd(), 'srv/redis-bridge/main.py')], {
      env: {
        ...process.env,
        REDIS_BRIDGE_HOST: '127.0.0.1',
        REDIS_BRIDGE_PORT: String(REDIS_PORT),
        REDIS_BACKEND: process.env.REDIS_BACKEND || 'inmemory',
      },
      stdio: 'inherit',
    });
    redisProcess.on('error', (err) => {
      console.warn('[bridge_manager] redisProcess error:', err.message);
    });
  }

  // Wait for both to be healthy before resolving
  await waitForHealth(PG_PORT);
  await waitForHealth(REDIS_PORT);
}

function checkHealth(port: number, cb: (alive: boolean) => void) {
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

function checkHealthAsync(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    checkHealth(port, resolve);
  });
}

function waitForHealth(port: number, maxRetries = 20, intervalMs = 500): Promise<void> {
  return new Promise((resolve, reject) => {
    let retries = 0;
    const check = async () => {
      const alive = await checkHealthAsync(port);
      if (alive) {
        resolve();
        return;
      }
      retries++;
      if (retries >= maxRetries) {
        reject(new Error(`Bridge on port ${port} failed to become healthy after ${maxRetries} retries`));
        return;
      }
      setTimeout(check, intervalMs);
    };
    check();
  });
}

// Proxy an incoming request buffer to a target port
export function proxyHttp(
  targetPort: number,
  targetPath: string,
  method: string,
  headers: Record<string, string | string[] | undefined>,
  bodyBuffer: Buffer | null,
  clientRes: http.ServerResponse
) {
  const options: http.RequestOptions = {
    hostname: '127.0.0.1',
    port: targetPort,
    path: targetPath,
    method,
    headers: {
      'content-type': headers['content-type'] || 'application/json',
      'content-length': bodyBuffer ? String(bodyBuffer.length) : '0',
    },
  };

  const req = http.request(options, (upstreamRes) => {
    clientRes.writeHead(upstreamRes.statusCode || 200, upstreamRes.headers);
    upstreamRes.pipe(clientRes);
  });

  req.on('error', (err) => {
    if (!clientRes.headersSent) {
      clientRes.writeHead(502, { 'Content-Type': 'application/json' });
      clientRes.end(JSON.stringify({ ok: false, error: `Bridge proxy error: ${err.message}` }));
    }
  });

  if (bodyBuffer && bodyBuffer.length > 0) {
    req.write(bodyBuffer);
  }
  req.end();
}
