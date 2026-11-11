/**
 * ssr.config.js — prerender config (prestruct law).
 *
 * `path` values become dist/<path>/index.html + sitemap entries after
 * `npm run build`. Keeping the route list HERE (not in code) is the
 * prestruct contract: adding a page is a config change, and the
 * prerender script renders every entry even if the router crashes —
 * pages without meta stay clean of stale tags.
 */
export default {
  siteUrl: 'https://synmergia.creadev.org',
  siteName: 'Synmergia',
  author: 'dhaupin',
  tagline: 'A free and open source spherical-world MMORPG',
  ogImage: 'https://synmergia.creadev.org/og-image.png', // 1200x630 card (scripts/gen_site_branding.py)
  // appLayoutPath: '/src/AppLayout.tsx', // prerender default already matches

  routes: [
    {
      path: '/',
      priority: '1.0',
      changefreq: 'weekly',
      meta: {
        title: 'Synmergia | A free and open source spherical-world MMORPG',
        description:
          'Plays in your browser. A hand-built planet with streamed terrain, living villages, real weather events, and honest worldbuilding. Free and open source.',
      },
    },
    {
      path: '/experiences',
      priority: '0.9',
      changefreq: 'weekly',
      meta: {
        title: 'What to expect | Synmergia',
        description:
          'A deeper look at the world: character creation, combat with real costs, exploration on one sphere, the Concord sky, ferries and mounts, weather and hordes, death, the economy, arenas, and the three worlds.',
      },
    },
    {
      path: '/codex',
      priority: '0.8',
      changefreq: 'weekly',
      meta: {
        title: 'Codex | Synmergia',
        description:
          'Browse everything the world is made of — classes, skills, species, enemies, items, recipes, mounts, the sky, and the hordes — read straight from the data files the server loads.',
      },
    },
    {
      path: '/lore',
      priority: '0.7',
      changefreq: 'monthly',
      meta: {
        title: 'Lore | Synmergia',
        description:
          'The story of the world: the Convergence that hummed and went silent, the Bloom that outlived its purpose, and the ancient machines left sleeping — with their wake-keys unwritten.',
      },
    },
    {
      path: '/opensource',
      priority: '0.7',
      changefreq: 'monthly',
      meta: {
        title: 'Open Source | Synmergia',
        description:
          'Synmergia is free, MIT-licensed, and built in the open. Why we opened the source, who we are looking for, and how to start contributing to the engine, the art, the world, and the tests.',
      },
    },
    {
      path: '/play',
      priority: '0.9',
      changefreq: 'weekly',
      meta: {
        title: 'Play Synmergia in your browser',
        description:
          'The WASM client loads in this tab — Godot 4.7 compiled for the web with threaded terrain workers. No account, no download, no install.',
      },
    },
    {
      path: '/rules',
      priority: '0.5',
      changefreq: 'yearly',
      meta: {
        title: 'Rules of the World | Synmergia',
        description:
          'How to play in good faith: no cheating or exploits, no harassment or real-world harm, respectful names. Enforcement, reporting, and what a ban means.',
      },
    },
    {
      path: '/privacy',
      priority: '0.4',
      changefreq: 'yearly',
      meta: {
        title: 'Privacy | Synmergia',
        description:
          'Synmergia collects nothing: no accounts, no analytics, no tracking. Local saves only, stored on your own device.',
      },
    },
    {
      path: '/terms',
      priority: '0.4',
      changefreq: 'yearly',
      meta: {
        title: 'Terms of Use | Synmergia',
        description:
          'Plain-language terms for the free, open-source Synmergia project and its website.',
      },
    },
    // Admin: restricted operator tooling. noindex is enforced in the
    // prerender script for any path starting with /admin — listed here
    // only so the gate page itself is rendered in dist/admin/ (waLL
    // page, never the dashboard).
    {
      path: '/admin',
      priority: '0.1',
      changefreq: 'yearly',
      noindex: true,
      meta: {
        title: 'Operator Access | Synmergia',
        description: 'Restricted operator tooling.',
      },
    },
  ],

  notFound: {
    heading: "This page doesn't exist",
    body: "The planet's faces are numbered and this isn't one of them. Head back to the homelands.",
    primaryCta: { label: 'Back to the homelands', href: '/' },
  },
};
