import { defineConfig, Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import path from 'path';
import fs from 'fs';
import { ensureBridgesRunning, proxyHttp } from './scripts/bridge_manager.ts';

function bridgeApiPlugin(): Plugin {
  return {
    name: 'bridge-api-plugin',
    async configureServer(server) {
      await ensureBridgesRunning();

      server.middlewares.use((req, res, next) => {
        const url = req.url || '';
        if (url.startsWith('/api/pg/') || url.startsWith('/api/redis/')) {
          const isPg = url.startsWith('/api/pg/');
          const targetPort = isPg ? 8080 : 8081;
          const targetPath = url.replace(isPg ? /^\/api\/pg/ : /^\/api\/redis/, '');

          const chunks: Buffer[] = [];
          req.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
          req.on('end', () => {
            const bodyBuffer = chunks.length > 0 ? Buffer.concat(chunks) : null;
            proxyHttp(targetPort, targetPath, req.method || 'GET', req.headers, bodyBuffer, res);
          });
          return;
        }
        next();
      });
    },
    async configurePreviewServer(server) {
      // In preview mode, bridges must already be running (started by
      // `npm run preview:with-bridges` or the Docker entrypoint).
      // We just wire up the proxy middleware here.
      server.middlewares.use((req, res, next) => {
        const url = req.url || '';
        if (url.startsWith('/api/pg/') || url.startsWith('/api/redis/')) {
          const isPg = url.startsWith('/api/pg/');
          const targetPort = isPg ? 8080 : 8081;
          const targetPath = url.replace(isPg ? /^\/api\/pg/ : /^\/api\/redis/, '');

          const chunks: Buffer[] = [];
          req.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
          req.on('end', () => {
            const bodyBuffer = chunks.length > 0 ? Buffer.concat(chunks) : null;
            proxyHttp(targetPort, targetPath, req.method || 'GET', req.headers, bodyBuffer, res);
          });
          return;
        }
        next();
      });
    },
  };
}

function serveGodotWeb(): Plugin {
  return {
    name: 'serve-godot-web',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = req.url ? req.url.split('?')[0] : '';
        if (url === '/web' || url.startsWith('/web/')) {
          const subPath = url.replace(/^\/web\/?/, '') || 'index.html';
          const filePath = path.resolve(process.cwd(), 'web', subPath);
          if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
            const ext = path.extname(filePath);
            const mimeTypes: Record<string, string> = {
              '.html': 'text/html',
              '.js': 'application/javascript',
              '.wasm': 'application/wasm',
              '.pck': 'application/octet-stream',
              '.css': 'text/css',
              '.svg': 'image/svg+xml',
              '.png': 'image/png',
              '.json': 'application/json',
              '.toml': 'text/plain',
            };
            res.setHeader('Content-Type', mimeTypes[ext] || 'application/octet-stream');
            res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
            res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
            return fs.createReadStream(filePath).pipe(res);
          }
        }
        next();
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), tailwindcss(), bridgeApiPlugin(), serveGodotWeb()],
  server: {
    host: '0.0.0.0',
    port: 3000,
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    },
  },
  preview: {
    host: '0.0.0.0',
    port: 3000,
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    },
  },
});


