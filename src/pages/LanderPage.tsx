import { Link } from 'react-router-dom';
import { usePckHash } from '../components/SiteLayout';
import godotData from '../data/godot_data.json';
import { buildCodex, CODEX_TOTAL } from '../lib/codex';

// Lander (honesty law): every claim here is traceable to code or data
// under game/. The counts come from game/data/*; the systems named
// (sphere terrain, the Concord sky clock, hordes, the ferry schedule)
// are the ones the world actually runs. No fake player counts, no
// invented quotes — the pack-freshness chip is the real "it's alive"
// signal.

// Counts are read from the synced godot_data.json (regenerated from
// game/data/*.tres on every build) so they cannot drift from the
// source, the way a hardcoded "163 skills" silently did.
const COUNTS = godotData.counts as Record<string, number>;
const PLAYABLE_CLASSES = Object.keys(godotData.classes).filter(
  (id) => /^(human|akkan|synthetic)_/.test(id),
).length;

// The codex is browsable at /codex; the lander shows a taste of it. Pull
// the categories once and surface a couple of headline groups.
const CODEX = buildCodex();
const CODEX_CATEGORY_COUNT = CODEX.length;
const CODEX_HEADLINES = ['classes', 'skills', 'enemies', 'recipes', 'mounts']
  .map((key) => CODEX.find((c) => c.key === key))
  .filter((c): c is NonNullable<typeof c> => Boolean(c));


/** What the world is, four ways (the load-bearing claims). */
const PILLARS = [
  {
    glyph: '◍',
    title: 'One real planet',
    body: 'A sphere 20 km in radius, not a flat map with a horizon painted on. Terrain streams face by face, rivers find the strait, and the snowline caps the peaks because the natural law put it there.',
  },
  {
    glyph: '◧',
    title: 'A world that keeps time',
    body: 'Day and night, a moon, tides, and the Concord sky clock all run on the same planetary clock. The sky is not scenery — the constellations are a calendar, and the calendar means something.',
  },
  {
    glyph: '⬡',
    title: 'Systems, not set dressing',
    body: 'Villages place real NPCs at real seats. Ferries run a closed-form schedule. Hordes march on a timer. Weather events open windows the whole shard answers. It is all data-driven.',
  },
  {
    glyph: '⇄',
    title: 'Open, and honest about it',
    body: 'MIT-licensed, built in the open. What players are told matches what happens — the terrain is deterministic from the world seed, and every claim on this page traces to a file in the repo.',
  },
];

/** The world, counted. Every number read from game/data. */
const WORLD_FACTS = [
  { n: String(COUNTS.zones), label: 'zones', sub: 'from Meadowhaven to the Sundered Sea' },
  { n: '3', label: 'worlds', sub: 'Synmergia, the pale stone, The Deep Root' },
  { n: String(PLAYABLE_CLASSES), label: 'playable classes', sub: 'across 3 species, plus GM seats' },
  { n: String(COUNTS.skills), label: 'skills', sub: 'class trees wired to real combat' },
  { n: String(COUNTS.enemies), label: 'enemy templates', sub: 'normal, elite, and world bosses' },
  { n: String(COUNTS.mounts), label: 'mounts', sub: 'ground, sky, and sea' },
];

/** What actually ships in the live world (traceable to game/ systems). */
const SYSTEMS = [
  {
    glyph: '◈',
    title: 'Spherical terrain',
    body: 'The planet is the map. Heights, rivers, and the strait come from a deterministic seed, so the same world boots the same way every time — and a new face loads as you walk onto it.',
  },
  {
    glyph: '✦',
    title: 'The Concord sky',
    body: 'A communal sky clock: constellations rise on schedule, the moon runs its phase, and the Ancient Door re-seals at dawn. Watch the sky, solve the day, and the Chronicle records a chapter.',
  },
  {
    glyph: '⚔',
    title: 'Combat with real math',
    body: 'Action combat resolved on the server: skills, auras, aggro, hitboxes, and damage all speak the same numbers. Level curve to 60, with a band past it that breathes instead of exploding.',
  },
  {
    glyph: '⚖',
    title: 'A working economy',
    body: 'Vendors, a blacksmith, a vault, a ferry, and per-entry currencies. One purse holds it all — gold, Junker Scrip, Concord Sigils — and every spend is a real debit with an honest refusal when the purse is short.',
  },
  {
    glyph: '☍',
    title: 'Weather and hordes',
    body: 'Weather events open windows off a live geomagnetic feed; five horde configs march on a timer and stir waves when a window opens. The world does things whether or not you are watching.',
  },
  {
    glyph: '⌁',
    title: 'Browser-first, no install',
    body: 'The web client is the primary client: Godot 4.7 compiled to WebAssembly with threaded terrain workers. Open a tab and you are on the planet — no download, no launcher.',
  },
];

/** The worlds under the same sky. */
const WORLDS = [
  {
    glyph: '◈',
    name: 'Synmergia',
    role: 'the home planet',
    body: 'The sphere you play on. Meadowhaven and the starter plains, Easthollow Village, Nexus Central, the Sundered Sea, and the Gloomwood above them.',
  },
  {
    glyph: '☾',
    name: 'the pale stone',
    role: 'the moon',
    body: 'A smaller body on a closed-form orbit. It rises and sets on the same clock the tides run on — the world\u2019s sky and its water agree.',
  },
  {
    glyph: '◆',
    name: 'The Deep Root',
    role: 'the underworld',
    body: 'The world\u2019s own depths: the Root Camp, a glow cistern, a lava underglow lake, and wilds that run on their own biome bands. Reachable, and not on the surface map.',
  },
];

export default function LanderPage() {
  const pckHash = usePckHash();
  return (
    <div>
      {/* Hero: nocturne field with the amber monolith mark */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 pointer-events-none" aria-hidden="true">
          <div className="absolute -top-24 left-1/2 -translate-x-1/2 w-72 h-72 rounded-full bg-accent/10 blur-3xl" />
          <div className="absolute inset-x-0 bottom-0 h-px bg-gradient-to-r from-transparent via-line to-transparent" />
        </div>
        <div className="relative max-w-6xl mx-auto px-4 pt-20 pb-16 text-center">
          <p className="text-xs tracking-[0.3em] uppercase text-accent/80 mb-6">
            A spherical open world
          </p>
          <h1 className="sr-only">Synmergia</h1>
          <img
            src="/branding/logo-synmergia-horizontal.png"
            alt="Synmergia"
            className="mx-auto w-[min(90vw,420px)] h-auto mb-6 drop-shadow-[0_0_30px_rgba(232,182,76,0.15)]"
          />
          <p className="mt-2 max-w-2xl mx-auto text-ink-soft text-base sm:text-lg leading-relaxed">
            A free and open source MMORPG on a hand-built planet: procedural terrain
            streamed face by face, villages that place real people at real seats,
            ferries that run on schedule, and a sky that means something. Runs in
            your browser.
          </p>
          <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
            <Link
              to="/play"
              className="px-6 py-3 rounded-lg bg-accent text-paper font-semibold hover:bg-accent-deep transition-colors shadow"
            >
              Play in browser
            </Link>
            <Link
              to="/codex"
              className="px-6 py-3 rounded-lg border border-line text-ink hover:border-accent hover:text-accent transition-colors"
            >
              Browse the Codex
            </Link>
          </div>
          <div className="mt-8 flex flex-wrap items-center justify-center gap-2">
            {['spherical world', 'browser-first', 'MIT-licensed', 'open source', 'deterministic seed'].map(
              (chip) => (
                <span
                  key={chip}
                  className="text-[11px] px-2.5 py-1 rounded-full border border-line text-ink-soft"
                >
                  {chip}
                </span>
              ),
            )}
          </div>
          <p className="mt-6 text-xs text-ink-soft font-mono">
            {pckHash ? `current build · ${pckHash}` : 'current build · fetching…'}
          </p>
        </div>
      </section>

      {/* Thesis band: the load-bearing claim (the same pull-quote shape the
          family landers carry — a kicker, an accent rule, accent emphasis). */}
      <section className="relative border-y border-line bg-surface/40">
        <div className="max-w-4xl mx-auto px-4 py-12 sm:py-14">
          <div className="border-l-2 border-accent pl-5 sm:pl-7">
            <p className="text-[11px] tracking-[0.3em] uppercase text-accent/80 mb-3">
              The thesis
            </p>
            <p className="font-display text-xl sm:text-2xl leading-snug text-ink">
              Most MMOs give you a map with a painted horizon and call it a world.
              Synmergia is <span className="text-accent">one sphere</span> — its terrain,
              its tides, its sky, and its seasons all derive from the{' '}
              <span className="text-accent">same seed</span>, so the world agrees with
              itself wherever you stand on it.
            </p>
          </div>
        </div>
      </section>

      {/* What it is */}
      <section className="max-w-6xl mx-auto px-4 py-14">
        <h2 className="font-display text-2xl sm:text-3xl mb-2">What it is</h2>
        <p className="text-sm text-ink-soft mb-8 max-w-2xl">
          Four things that are true of the world, and the reason each one matters.
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {PILLARS.map((p) => (
            <div key={p.title} className="rounded-xl border border-line bg-surface p-5">
              <h3 className="font-display text-lg mb-2">
                <span className="text-accent mr-2" aria-hidden="true">{p.glyph}</span>
                {p.title}
              </h3>
              <p className="text-sm text-ink-soft leading-relaxed">{p.body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* The world, counted */}
      <section className="max-w-6xl mx-auto px-4 pb-14">
        <h2 className="font-display text-2xl sm:text-3xl mb-2">The world, counted</h2>
        <p className="text-sm text-ink-soft mb-8 max-w-2xl">
          Straight from the data files the server loads. Nothing here is aspirational
          — it is what ships.
        </p>
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
          {WORLD_FACTS.map((f) => (
            <div key={f.label} className="rounded-xl border border-line bg-surface p-5">
              <p className="font-display text-3xl text-accent leading-none">{f.n}</p>
              <p className="mt-2 text-sm font-semibold">{f.label}</p>
              <p className="mt-1 text-xs text-ink-soft leading-relaxed">{f.sub}</p>
            </div>
          ))}
        </div>
        <p className="mt-6 text-sm text-ink-soft">
          Every one of these is browsable, entry by entry, in the{' '}
          <Link to="/codex" className="text-accent hover:underline">
            Codex
          </Link>{' '}
          — {CODEX_TOTAL.toLocaleString()} entries across {CODEX_CATEGORY_COUNT} categories.
        </p>
      </section>

      {/* The Codex, at a glance */}
      <section className="max-w-6xl mx-auto px-4 pb-14">
        <div className="flex flex-wrap items-end justify-between gap-3 mb-8">
          <div>
            <h2 className="font-display text-2xl sm:text-3xl mb-2">Browse the world itself</h2>
            <p className="text-sm text-ink-soft max-w-2xl">
              The Codex reads the same data files the server loads — every class, skill,
              enemy, recipe, and mount, with its real numbers. No marketing layer.
            </p>
          </div>
          <Link
            to="/codex"
            className="px-5 py-2.5 rounded-lg border border-line text-ink text-sm hover:border-accent hover:text-accent transition-colors shrink-0"
          >
            Open the Codex
          </Link>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
          {CODEX_HEADLINES.map((c) => (
            <Link
              key={c.key}
              to="/codex"
              className="rounded-xl border border-line bg-surface p-5 hover:border-accent/60 transition-colors"
            >
              <p className="font-display text-2xl text-accent leading-none">{c.entries.length}</p>
              <p className="mt-2 text-sm font-semibold">{c.label}</p>
              <p className="mt-1 text-xs text-ink-soft leading-relaxed line-clamp-2">{c.blurb}</p>
            </Link>
          ))}
        </div>
      </section>

      {/* What actually ships */}
      <section className="max-w-6xl mx-auto px-4 pb-14">
        <h2 className="font-display text-2xl sm:text-3xl mb-2">Systems, not set dressing</h2>
        <p className="text-sm text-ink-soft mb-8 max-w-2xl">
          The parts of the world that are running right now, in the live build.
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {SYSTEMS.map((s) => (
            <div key={s.title} className="rounded-xl border border-line bg-surface p-5">
              <h3 className="font-display text-lg mb-2">
                <span className="text-accent mr-2" aria-hidden="true">{s.glyph}</span>
                {s.title}
              </h3>
              <p className="text-sm text-ink-soft leading-relaxed">{s.body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* The worlds */}
      <section className="max-w-6xl mx-auto px-4 pb-14">
        <h2 className="font-display text-2xl sm:text-3xl mb-2">One sky, three worlds</h2>
        <p className="text-sm text-ink-soft mb-8 max-w-2xl">
          The planet, its moon, and its own depths — each a declared world, all on the
          same clock.
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {WORLDS.map((w) => (
            <div key={w.name} className="rounded-xl border border-line bg-surface p-5">
              <h3 className="font-display text-lg mb-1">
                <span className="text-accent mr-2" aria-hidden="true">{w.glyph}</span>
                {w.name}
              </h3>
              <p className="text-[11px] uppercase tracking-[0.2em] text-ink-soft mb-3">
                {w.role}
              </p>
              <p className="text-sm text-ink-soft leading-relaxed">{w.body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Built in the open */}
      <section className="max-w-4xl mx-auto px-4 pb-20">
        <div className="rounded-2xl border border-line bg-surface p-8">
          <h2 className="font-display text-2xl mb-4">Built in the open</h2>
          <p className="text-sm text-ink-soft leading-relaxed max-w-2xl">
            The world runs on a law system: deterministic terrain from the world seed,
            weather events off a real geomagnetic feed, and a strict understanding that
            what players are told should match what happens. Every commit is public —
            follow along, file an issue, or fork the planet.
          </p>
          <div className="mt-6 flex flex-wrap items-center gap-3">
            <a
              href="https://github.com/dhaupin/synmergia"
              target="_blank"
              rel="noreferrer"
              className="px-5 py-2.5 rounded-lg border border-line text-ink text-sm hover:border-accent hover:text-accent transition-colors"
            >
              GitHub
            </a>
            <Link
              to="/rules"
              className="px-5 py-2.5 rounded-lg border border-line text-ink text-sm hover:border-accent hover:text-accent transition-colors"
            >
              Rules
            </Link>
            <span className="text-xs text-ink-soft">
              Godot Engine · WebAssembly · MIT-licensed · deterministic world seed
            </span>
          </div>
        </div>
      </section>

      {/* Final CTA band */}
      <section className="border-t border-line bg-surface/40">
        <div className="max-w-3xl mx-auto px-4 py-14 text-center">
          <h2 className="font-display text-2xl sm:text-3xl mb-3">
            Step onto the planet.
          </h2>
          <p className="text-sm text-ink-soft mb-8">
            It loads in this tab — no download, no launcher. Free, and open source.
          </p>
          <div className="flex flex-wrap items-center justify-center gap-3">
            <Link
              to="/play"
              className="px-6 py-3 rounded-lg bg-accent text-paper font-semibold hover:bg-accent-deep transition-colors shadow"
            >
              Play in browser
            </Link>
            <a
              href="https://github.com/dhaupin/synmergia"
              target="_blank"
              rel="noreferrer"
              className="px-6 py-3 rounded-lg border border-line text-ink hover:border-accent hover:text-accent transition-colors"
            >
              View source
            </a>
          </div>
        </div>
      </section>
    </div>
  );
}
