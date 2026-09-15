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
        }

        // Wait a short tick for boot if either was newly spawned
        setTimeout(() => {
          resolve({ pgPort: PG_PORT, redisPort: REDIS_PORT });
        }, 300);
      });
    });
  });
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
