/**
 * Preserve the site's noindex law for restricted routes.
 *
 * prestruct 1.5.1 has no per-route noindex switch (route.noindex is ignored),
 * and its sitemap includes every configured route. This postBuild hook adds
 * the robots directive to each route marked noindex:true in ssr.config.js and
 * drops those URLs from the generated sitemap.
 */
import fs from 'node:fs';
import path from 'node:path';
import config from '../ssr.config.js';

const DIST = path.resolve('dist');
const NOINDEX =
  '<meta name="robots" content="noindex, nofollow, noarchive, nosnippet, noimageindex" />';
const restricted = (config.routes || []).filter((route) => route && route.noindex === true);

for (const route of restricted) {
  if (typeof route.path !== 'string') continue;
  const file =
    route.path === '/'
      ? path.join(DIST, 'index.html')
      : path.join(DIST, route.path.slice(1), 'index.html');
  if (!fs.existsSync(file)) continue;

  let html = fs.readFileSync(file, 'utf8');
  html = html.replace(/\s*<meta\s+name=["']robots["'][^>]*>\s*/gi, '\n  ');
  html = html.replace('</head>', `  ${NOINDEX}\n  </head>`);
  fs.writeFileSync(file, html);
}

const sitemapPath = path.join(DIST, 'sitemap.xml');
if (restricted.length > 0 && fs.existsSync(sitemapPath)) {
  const origin = (config.siteUrl || '').replace(/\/$/, '');
  let xml = fs.readFileSync(sitemapPath, 'utf8');
  for (const route of restricted) {
    if (typeof route.path !== 'string') continue;
    const loc = `<loc>${origin}${route.path === '/' ? '' : route.path}</loc>`;
    xml = xml.replace(/\n  <url>[\s\S]*?<\/url>/g, (block) => (block.includes(loc) ? '' : block));
  }
  fs.writeFileSync(sitemapPath, xml);
}

if (restricted.length > 0) {
  console.log(`[postbuild] applied noindex to ${restricted.length} restricted route(s)`);
}
