/**
 * scripts/prerender.js — prestruct law, Synmergia adaptation.
 *
 * Runs after `vite build` via `npm run build`. Uses Vite's
 * ssrLoadModule to render each route to static HTML.
 *
 * Why ssrLoadModule instead of `vite build --ssr`:
 *   ssrLoadModule resolves all imports through Vite's unified module
 *   registry. This guarantees a single instance of react-router-dom —
 *   StaticRouter and Routes share the same context, so location
 *   propagates correctly. A compiled SSR bundle would silently render
 *   every route as '/' with no error (see prestruct AGENTS.md).
 *
 * Output (routes from ssr.config.js):
 *   dist/index.html           → /
 *   dist/<route>/index.html   → each other route
 *   dist/404.html             → served by CF Pages for unmatched routes (HTTP 404)
 *   dist/sitemap.xml          → generated from ssr.config routes
 *
 * Fails gracefully — exits 0 on fatal error so the Pages deploy
 * continues as SPA rather than failing entirely.
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const DIST = path.join(ROOT, 'dist');

// ── Load config ─────────────────────────────────────────────

let config;
try {
  config = (await import('../ssr.config.js')).default;
} catch (err) {
  console.error('[prerender] Could not load ssr.config.js:', err.message);
  process.exit(0);
}

const {
  siteUrl,
  siteName = 'Site',
  routes: ROUTES = [],
  appLayoutPath = '/src/AppLayout.tsx',
} = config;

if (!siteUrl) {
  console.error('[prerender] siteUrl is required in ssr.config.js');
  process.exit(0);
}
if (!ROUTES.length) {
  console.warn('[prerender] No routes defined in ssr.config.js — skipping');
  process.exit(0);
}
const invalidRoutes = ROUTES.filter((r) => !r.path || !r.path.startsWith('/'));
if (invalidRoutes.length > 0) {
  console.error('[prerender] Invalid routes found:', invalidRoutes.map((r) => r.path).join(', '));
  process.exit(0);
}

// ── Build cache: intentionally disabled for this site ───────
// The example's route cache is an anti-pattern at the bundle-hash
// level: cached HTML embeds the BUNDLE NAME of whatever build rendered
// it, so a code change (new asset hash) plus a cache hit writes the
// OLD bundle reference over the fresh shell — a build that references
// a nonexistent script. Outputs here are tiny (5 routes), so the
// cache bought nothing anyway. Every build renders fresh.
const FORCE = true; // kept for the --force flag's compatibility

// ── Meta injection ──────────────────────────────────────────

function injectMeta(html, meta, routePath) {
  // Prevent regex backreference expansion when dynamic values are used in replacement strings.
  const escapeReplacement = (s) => String(s || '').replace(/\$/g, '$$$$');

  const title = escapeReplacement(meta.title);
  const desc = escapeReplacement(meta.description);
  const ogImage = escapeReplacement(meta.ogImage || config.ogImage || '');
  const url = escapeReplacement(`${siteUrl}${routePath === '/' ? '' : routePath}`);

  if (title) {
    html = html.replace(/<title>[^<]*<\/title>/, `<title>${title}</title>`);
    html = html.replace(/(<meta\s+property="og:title"\s+content=")[^"]*(")/s, `$1${title}$2`);
    html = html.replace(/(<meta\s+name="twitter:title"\s+content=")[^"]*(")/s, `$1${title}$2`);
  }
  if (desc) {
    html = html.replace(/(<meta\s+name="description"\s+content=")[^"]*(")/s, `$1${desc}$2`);
    html = html.replace(/(<meta\s+property="og:description"\s+content=")[^"]*(")/s, `$1${desc}$2`);
    html = html.replace(/(<meta\s+name="twitter:description"\s+content=")[^"]*(")/s, `$1${desc}$2`);
  }
  html = html.replace(/(<meta\s+property="og:url"\s+content=")[^"]*(")/s, `$1${url}$2`);
  html = html.replace(/(<link\s+rel="canonical"\s+href=")[^"]*(")/s, `$1${url}$2`);
  if (ogImage) {
    html = html.replace(/(<meta\s+property="og:image"\s+content=")[^"]*(")/s, `$1${ogImage}$2`);
    html = html.replace(/(<meta\s+name="twitter:image"\s+content=")[^"]*(")/s, `$1${ogImage}$2`);
  }

  // Admin/noindex law: restricted routes (admin gate) must never be
  // indexed — they are operator tooling, not site content. Anchored on
  // </head> because the shell carries no <meta name="author"> anchor.
  if (routePath.startsWith('/admin')) {
    html = html.replace(/<meta\s+name="robots"\s+content="[^"]*"\s*\/?>/s, '');
    html = html.replace(
      '</head>',
      '<meta name="robots" content="noindex, nofollow, noarchive, nosnippet, noimageindex" />\n  </head>'
    );
  }

  return html;
}

// ── Sitemap ─────────────────────────────────────────────────

function escapeXml(unsafe) {
  if (!unsafe) return '';
  return String(unsafe)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function generateSitemap(routes) {
  const now = new Date().toISOString().split('T')[0];
  const urls = routes
    .filter((r) => !r.noindex)
    .map(
      (r) => `
  <url>
    <loc>${escapeXml(siteUrl)}${r.path === '/' ? '' : escapeXml(r.path)}</loc>
    <lastmod>${now}</lastmod>
    <changefreq>${r.changefreq || 'monthly'}</changefreq>
    <priority>${r.priority || '0.5'}</priority>
  </url>`
    )
    .join('');
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}
</urlset>`;
}

// ── 404 page ────────────────────────────────────────────────
// id="root-404" (not "root") so react does NOT try to hydrate it as
// SSR content (it is plain static HTML with the bundle stripped).

function generate404(shell) {
  const nf = config.notFound || {};
  const heading = nf.heading || 'Page not found.';
  const body =
    nf.body || "That page doesn't exist — the planet's faces are numbered and this isn't one of them.";
  const primaryLabel = nf.primaryCta?.label || 'Back to the homelands';
  const primaryHref = nf.primaryCta?.href || '/';

  const bodyLines = [
    '<div id="root-404">',
    '  <div style="min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:4rem 2rem;background:#0b0e14;color:#e6e2d8;font-family:system-ui,sans-serif">',
    `    <h1 style="font-family:serif;font-size:2.5rem;font-weight:800;margin-bottom:1rem;color:#e8b64c">${heading}</h1>`,
    `    <p style="max-width:480px;font-size:1.05rem;line-height:1.7;margin-bottom:2rem;color:#9aa3b2">${body}</p>`,
    `    <a href="${primaryHref}" style="display:inline-flex;align-items:center;padding:0.75rem 1.75rem;background:#e8b64c;color:#0b0e14;font-weight:700;font-size:0.9rem;letter-spacing:0.05em;text-transform:uppercase;border-radius:8px;text-decoration:none">${primaryLabel}</a>`,
    '  </div>',
    '</div>',
  ];

  let html = shell.replace('<div id="root"></div>', bodyLines.join('\n'));
  html = html.replace(/<title>[^<]*<\/title>/, `<title>Page Not Found | ${siteName}</title>`);
  html = html.replace(/(<meta\s+name="description"\s+content=")[^"]*(")/s, `$1The page you were looking for does not exist.$2`);
  html = html.replace(/(<meta\s+property="og:title"\s+content=")[^"]*(")/s, `$1Page Not Found | ${siteName}$2`);
  html = html.replace(/(<link\s+rel="canonical"\s+href=")[^"]*(")/s, `$1${siteUrl}/$2`);
  html = html.replace(/<meta\s+name="robots"\s+content="[^"]*"\s*\/?>/s, '');
  html = html.replace(
    '<meta name="author"',
    '<meta name="robots" content="noindex, nofollow, noarchive, nosnippet, noimageindex" />\n    <meta name="author"'
  );
  // Strip the React bundle — 404 is pure static HTML, no React needed.
  html = html.replace(/<script type="module"[^>]*><\/script>/, '');

  return html;
}

// ── Main ────────────────────────────────────────────────────

async function prerender() {
  console.log('\n[prerender] Starting static HTML generation...');

  const { createServer } = await import('vite');
  const { renderToString } = await import('react-dom/server');
  const React = (await import('react')).default;
  const { StaticRouter } = await import('react-router-dom/server.js');

  const vite = await createServer({
    root: ROOT,
    server: { middlewareMode: true },
    appType: 'custom',
    customLogger: {
      info: () => {},
      warn: (msg) => {
        if (!msg.includes('ExperimentalWarning')) process.stderr.write('[prerender:warn] ' + msg + '\n');
      },
      error: (msg) => process.stderr.write('[prerender:err] ' + msg + '\n'),
      clearScreen: () => {},
      hasErrorLogged: () => false,
      hasWarned: false,
      warnOnce: () => {},
    },
  });

  try {
    const { default: AppLayout } = await vite.ssrLoadModule(appLayoutPath);

    const indexPath = path.join(DIST, 'index.html');
    if (!fs.existsSync(indexPath)) {
      console.error('[prerender] dist/index.html not found — run vite build first');
      process.exit(0);
    }

    const shell = fs.readFileSync(indexPath, 'utf-8');
    let succeeded = 0;

    for (const route of ROUTES) {
      // Cached path: reuse if not --force
      if (!FORCE && cache[route.path]) {
        const cachedHtml = cache[route.path].html;
        if (route.path === '/') {
          fs.writeFileSync(path.join(DIST, 'index.html'), cachedHtml, 'utf-8');
        } else {
          const dir = path.join(DIST, route.path.slice(1));
          fs.mkdirSync(dir, { recursive: true });
          fs.writeFileSync(path.join(dir, 'index.html'), cachedHtml, 'utf-8');
        }
        console.log(`[prerender] ◯ ${route.path} (cached)`);
        succeeded++;
        continue;
      }

      try {
        const appHtml = renderToString(
          React.createElement(
            StaticRouter,
            { location: route.path },
            React.createElement(AppLayout)
          )
        );

        let html = shell.replace(
          '<div id="root"></div>',
          `<div id="root" data-server-rendered="true">${appHtml}</div>`
        );

        html = injectMeta(html, route.meta || {}, route.path);

        if (route.path === '/') {
          fs.writeFileSync(path.join(DIST, 'index.html'), html, 'utf-8');
        } else {
          const dir = path.join(DIST, route.path.slice(1));
          fs.mkdirSync(dir, { recursive: true });
          fs.writeFileSync(path.join(dir, 'index.html'), html, 'utf-8');
        }

        console.log(`[prerender] ✓ ${route.path}`);
        succeeded++;
      } catch (err) {
        console.error(`[prerender] ✗ ${route.path}: ${err.message}`);
      }
    }

    fs.writeFileSync(path.join(DIST, '404.html'), generate404(shell), 'utf-8');
    console.log('[prerender] ✓ /404.html');

    fs.writeFileSync(path.join(DIST, 'sitemap.xml'), generateSitemap(ROUTES), 'utf-8');
    console.log('[prerender] ✓ /sitemap.xml');

    console.log(`[prerender] Done. ${succeeded}/${ROUTES.length} pages rendered.\n`);
  } finally {
    await vite.close();
  }
}

prerender().catch((err) => {
  console.warn('[prerender] Fatal — deploying as SPA:', err.message);
  process.exit(0);
});
