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
      // Build-mode guard (Cloudflare Pages hang, 2026-10-19): the
      // prerender also creates a Vite server (middlewareMode) to
      // ssrLoadModule the app, which fires this hook on EVERY build.
      // Starting the bridge sidecars there spawned python3 children
      // with live stdio handles npm never reaps -> the Pages build
      // printed the bridge banner and hung forever. Bridges are only
      // meaningful when a server is actually SERVING requests; the
      // prerender never calls /api/* (React SSR is pure). Detect the
      // programmatic server and skip startup.
      if (!server.config.server.middlewareMode) {
        await ensureBridgesRunning();
      } else {
        // eslint-disable-next-line no-console
        console.log('[bridge-api-plugin] middlewareMode server: skipping bridge spawn');
      }

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

function copyGodotWebToDist(): Plugin {
  return {
    name: 'copy-godot-web-to-dist',
    apply: 'build',
    closeBundle() {
      // The Godot WASM client lives in web/ (index.html + game.js +
      // game.pck + workers). Vite only copies public/ into dist/, so
      // production deploys lost the engine unless this runs. Ship the
      // whole web/ directory as-is... except files beyond Cloudflare
      // Pages' 25 MiB per-file asset cap (validated after build; a
      // 38 MB game.wasm rejected the whole deploy 2026-10-19). Those
      // are streamed from R2 by the Pages Functions in functions/game/
      // instead — same URL, no client change.
      const srcDir = path.resolve(process.cwd(), 'web');
      const destDir = path.resolve(process.cwd(), 'dist', 'game');
      if (!fs.existsSync(srcDir)) return;
      const MAX_FILE = 25 * 1024 * 1024; // Pages per-file cap, inclusive
      fs.cpSync(srcDir, destDir, { recursive: true });
      const excluded: string[] = [];
      const audit = (dir: string) => {
        for (const f of fs.readdirSync(dir)) {
          const p = path.join(dir, f);
          if (fs.statSync(p).isDirectory()) {
            audit(p);
          } else if (fs.statSync(p).size > MAX_FILE) {
            excluded.push(path.relative(destDir, p) + ' (' + (fs.statSync(p).size / 1048576).toFixed(1) + ' MiB)');
            fs.rmSync(p);
          }
        }
      };
      audit(destDir);
      for (const name of excluded) {
        console.log(`[copy-godot-web] EXCLUDED >25MiB: ${name} -> served from R2 via functions/game/`);
      }
      if (excluded.length > 0) {
        fs.writeFileSync(path.join(destDir, '_oversize.txt'), excluded.join('\n') + '\n');
      }
      console.log(`[copy-godot-web] web/ -> dist/game/ (${fs.readdirSync(destDir).length} entries)`);
    },
  };
}

// One handler for BOTH the dev server and the preview server so the
// two never drift (they were pasted copies).
//
// Round 8, item 10 (tab-away refresh): every /web response used to be
// `Cache-Control: no-cache` with NO Content-Length and no validators,
// so a browser tab-discard (Memory Saver / mobile memory pressure)
// came back as a full re-download of the 38 MB wasm + pack. Now:
//   - Content-Length is always set (this also fixes HEAD, which the
//     shell uses to size the boot progress bar), and HEAD gets no body.
//   - Freshness anchors stay no-cache: index.html + game.pck.hash.
//   - The content-addressed pack (game.pck?v=<hash>) is immutable --
//     the hash in the query IS the cache key, exactly one fetch ever.
//   - game.wasm gets a 1-day TTL: the engine binary only changes on a
//     Godot export bump, and the no-cache shell always re-anchors it.
function godotWebRequestHandler(req: any, res: any, next: any): void {
  // Single-domain law: the site is served at /, the raw game client at
  // /game/ (no second subdomain, no cross-origin COOP/COEP friction for
  // SharedArrayBuffer). /web/ keeps working for old bookmarks.
  const url = req.url ? req.url.split('?')[0] : '';
  const isGame = url === '/game' || url.startsWith('/game/');
  const isWeb = url === '/web' || url.startsWith('/web/');
  if (isGame || isWeb) {
    const subPath = url.replace(/^\/(game|web)\/?/, '') || 'index.html';
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
        '.hash': 'text/plain',
      };
      res.setHeader('Content-Type', mimeTypes[ext] || 'application/octet-stream');
      res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
      res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
      // Cache law (see block comment above): the pack is
      // content-addressed by its ?v=<hash> query -- immutable; the
      // named binaries and anchors stay honest so a new CI pack
      // commit-back is picked up by the next reload.
      const rawUrl: string = req.url || '';
      const isContentAddressed = subPath.endsWith('.pck') && rawUrl.includes('?v=');
      if (isContentAddressed) {
        res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
      } else if (ext === '.wasm') {
        res.setHeader('Cache-Control', 'public, max-age=86400');
      } else {
        res.setHeader('Cache-Control', 'no-cache');
      }
      res.setHeader('Content-Length', String(fs.statSync(filePath).size));
      if (req.method === 'HEAD') {
        res.end();
        return;
      }
      return fs.createReadStream(filePath).pipe(res);
    }
  }
  next();
}

function serveGodotWeb(): Plugin {
  return {
    name: 'serve-godot-web',
    configureServer(server) {
      server.middlewares.use(godotWebRequestHandler);
    },
    configurePreviewServer(server) {
      server.middlewares.use(godotWebRequestHandler);
    },
  };
}

export default defineConfig({
  plugins: [react(), tailwindcss(), bridgeApiPlugin(), serveGodotWeb(), copyGodotWebToDist()],
  server: {
    host: '0.0.0.0',
    port: 3000,
    allowedHosts: true,
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    },
  },
  preview: {
    host: '0.0.0.0',
    port: 3000,
    allowedHosts: true,
    headers: {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    },
  },
});


