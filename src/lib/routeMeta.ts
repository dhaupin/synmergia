// Per-route document titles. The prerenderer bakes these same strings into
// the static HTML from `ssr.config.js` `routes[].meta.title`; this map is the
// client-side twin, so a client-side route change updates `document.title`
// too (WCAG 2.4.2 Page Titled). Keep the values in sync with ssr.config.js.
export const ROUTE_TITLES: Record<string, string> = {
  '/': 'Synmergia | A free and open source spherical-world MMORPG',
  '/experiences': 'What to expect | Synmergia',
  '/codex': 'Codex | Synmergia',
  '/lore': 'Lore | Synmergia',
  '/opensource': 'Open Source | Synmergia',
  '/play': 'Play Synmergia in your browser',
  '/rules': 'Rules of the World | Synmergia',
  '/accessibility': 'Accessibility | Synmergia',
  '/agents': 'Agents | Synmergia',
  '/privacy': 'Privacy | Synmergia',
  '/terms': 'Terms of Use | Synmergia',
  '/admin': 'Operator Access | Synmergia',
};

export const routeTitle = (pathname: string): string =>
  ROUTE_TITLES[pathname] ?? 'Synmergia';
