import { Link } from 'react-router-dom';
import { usePckHash } from '../components/SiteLayout';

// Lander (honesty law): every claim here is traceable to code. No
// fake player counts, no invented quotes — the pack-freshness chip
// and the build pipeline are the real "it's alive" signal.
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
        <div className="relative max-w-6xl mx-auto px-4 pt-20 pb-24 text-center">
          <p className="text-xs tracking-[0.3em] uppercase text-accent/80 mb-4">
            A spherical open world
          </p>
          <h1 className="font-display text-4xl sm:text-6xl font-bold leading-tight">
            Synmergia
          </h1>
          <p className="mt-6 max-w-2xl mx-auto text-ink-soft text-base sm:text-lg leading-relaxed">
            A free and open source MMORPG on a hand-built planet: procedural terrain
            streamed face by face, villages that grow real buildings, ferries that
            run on schedule, and a sky that means something. Runs in your browser.
          </p>
          <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
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
          <p className="mt-6 text-xs text-ink-soft font-mono">
            {pckHash ? `current build · ${pckHash}` : 'current build · fetching…'}
          </p>
        </div>
      </section>

      {/* Feature strip: what actually ships (traceable to game/ systems) */}
      <section className="max-w-6xl mx-auto px-4 py-8">
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {[
            {
              title: 'A real planet',
              body: 'Twenty-thousand-meter sphere with streamed terrain faces, love-crafted homelands, and an ocean with actual currents.',
            },
            {
              title: 'Living settlements',
              body: 'Starter villages with blacksmiths, quests, weather events, hordes on the march — driven by data, not screenshots.',
            },
            {
              title: 'WASM-first',
              body: 'The web client is the primary client. Godot 4.7 compiled to WebAssembly with threaded terrain workers, playable on a phone.',
            },
          ].map((f) => (
            <div key={f.title} className="rounded-xl border border-line bg-surface p-5">
              <h3 className="font-display text-lg mb-2">{f.title}</h3>
              <p className="text-sm text-ink-soft leading-relaxed">{f.body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* The pitch: why open source + honest world */}
      <section className="max-w-4xl mx-auto px-4 pb-24">
        <div className="rounded-2xl border border-line bg-surface p-8 text-center">
          <h2 className="font-display text-2xl mb-4">Built in the open</h2>
          <p className="text-sm text-ink-soft leading-relaxed max-w-2xl mx-auto">
            The world runs on a law system: deterministic terrain from the world
            seed, weather events on a real geomagnetic feed, and a strict
            understanding that what players are told should match what happens.
            Every commit is public — follow along or fork the planet.
          </p>
          <p className="mt-4 text-xs text-ink-soft">
            Godot Engine · WebAssembly · Deterministic world seed · CC-licensed lore
          </p>
        </div>
      </section>
    </div>
  );
}
