/**
 * ssr.config.js — prerender config (prestruct law).
 *
 * `path` values become dist/<path>/index.html + sitemap entries after
 * `prestruct build`. Keeping the route list HERE (not in code) is the
 * prestruct contract: adding a page is a config change.
 */
export default {
  siteUrl: 'https://synmergia.creadev.org',
  siteName: 'Synmergia',
  author: 'dhaupin',
  tagline: 'A free and open source spherical-world MMORPG',
  ogImage: {
    url: 'https://synmergia.creadev.org/og-image.png', // 1200x630 card (scripts/gen_site_branding.py)
    width: 1200,
    height: 630,
    alt: 'Synmergia — a free and open source spherical-world MMORPG',
  },
  appLayoutPath: '/src/AppLayout.tsx', // prestruct defaults to .jsx; this site is TSX

  // Admin gate: prestruct 1.5.1 has no per-route noindex switch, so the
  // postBuild hook adds the robots directive and drops restricted URLs from
  // the generated sitemap after prerendering.
  runHooks: true,
  hooks: {
    postBuild: ['node scripts/postbuild-noindex.mjs'],
  },
  llms: false,

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
          'The WASM client loads in this tab — Godot 4.7 compiled for the web with threaded terrain workers. Early access is key-gated; no download, no install.',
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
      path: '/accessibility',
      priority: '0.5',
      changefreq: 'yearly',
      meta: {
        title: 'Accessibility | Synmergia',
        description:
          'Named controls, real focus order, and settings that change the surface: high contrast, text scale, reduce motion, colorblind correction, screen shake, flash effects.',
      },
    },
    {
      path: '/agents',
      priority: '0.5',
      changefreq: 'yearly',
      meta: {
        title: 'Agents | Synmergia',
        description:
          'Programs can join as players: their own character, the same actions everyone uses, consequential acts gated for human approval, and off until someone runs one.',
      },
    },
    {
      path: '/privacy',
      priority: '0.4',
      changefreq: 'yearly',
      meta: {
        title: 'Privacy | Synmergia',
        description:
          'What Synmergia stores: the account minimum (email, display name, hashed password), session records, and gameplay anti-cheat. No third-party analytics or ads.',
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
    // Admin: restricted operator tooling. noindex and sitemap removal are
    // enforced by scripts/postbuild-noindex.mjs after prestruct prerenders
    // the route; keep noindex: true here as the source of truth.
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
