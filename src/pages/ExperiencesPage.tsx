import { Link } from 'react-router-dom';
import { ArrowLeft, ArrowRight } from 'lucide-react';

import godotData from '../data/godot_data.json';

// The Experiences page: a deeper, honest walk-through of what a player
// actually meets -- grounded in the same godot_data.json the codex and
// the lander read, so no promise here outruns the build. The narrative
// is prose; the numbers are derived.

const counts = (godotData as any).counts as Record<string, number>;

// Playable classes are the species-prefixed authored rows (the sync also
// emits bare base-archetype aliases that point at the same .tres).
const CLASS_ROWS = Object.keys((godotData as any).classes || {});
const PLAYABLE_CLASSES = CLASS_ROWS.filter((id) =>
  /^(human|akkan|synthetic)_/.test(id),
).length;

interface Section {
  kicker: string;
  title: string;
  body: string[];
  aside?: string;
}

const SECTIONS: Section[] = [
  {
    kicker: 'Before you log in',
    title: 'Create a character that is a person, not a preset',
    body: [
      `Three species share the planet — Human, Akkan, and Synthetic — and each brings ${Math.round(
        PLAYABLE_CLASSES / 3,
      )} classes of its own. Species is not a coat of paint: it sets your stat frame, your home zone, and who starts out friendly.`,
      'Your class decides your role in a fight and the resource you spend to hold it. A Bulwark holds a line; a Sorcerer answers it; a Conduit keeps everyone upright. You pick a role, not a damage number.',
    ],
    aside: `${PLAYABLE_CLASSES} playable classes across ${counts.species} species`,
  },
  {
    kicker: 'The first hour',
    title: 'You wake up somewhere that already works',
    body: [
      'You start in the homelands with a starter kit already in your bag and a village that has real people at real seats. Vendors open real shops, quest-givers hold real conversations, and the road out of town goes somewhere.',
      'Quests are concrete: talk to the elder, hunt the wolves, gather the petals, carry the word to the next village. The tracker tells you where, the world tells you why.',
    ],
    aside: `${counts.zones} named zones · ${counts.quests} quests shipped`,
  },
  {
    kicker: 'Combat',
    title: 'Skills with real weight, not fire-and-forget',
    body: [
      'Every ability has a real mana cost, a real cooldown, and a real cast time. Some are instant, some channel, some land on the ground where you aim them. What the tooltip promises is what actually happens when you press it.',
      'Fights read clearly: you see the hit, the miss, the crit, and the kill in the combat log, and a threat meter that actually matters when you are standing next to something that hits back.',
    ],
    aside: `${counts.skills} skills · ${counts.enemies} enemies · ${counts.world_bosses} world bosses`,
  },
  {
    kicker: 'Exploration',
    title: 'One endless horizon, no loading screens',
    body: [
      'The world is a single planet, not a set of stitched-together maps. The land rolls out around you as you walk — hills, rivers, and snowlines that all agree with each other, so the ground under your feet always makes sense.',
      'Discover waypoints and the map becomes a fast-travel network. Click a marker and you are moving; the horizon you can see is the horizon you can reach.',
    ],
    aside: 'A whole world, with no edges',
  },
  {
    kicker: 'The sky',
    title: 'A sky that means something',
    body: [
      'Above everything runs the Concord: a shared sky clock the whole world reads together. Its signs turn on a common schedule, and an ancient door re-seals at every dawn until someone solves the day.',
      'Each solved day writes a chapter into the Chronicle — the world keeps a real record of what its players figured out. There is a daily beat to the sky, and everyone in the world feels it at once.',
    ],
    aside: `${counts.signs} sky signs · ${counts.acts} chronicle acts · ${counts.mysteries} mysteries`,
  },
  {
    kicker: 'Getting around',
    title: 'Ferries on a schedule, mounts that carry you',
    body: [
      'The strait is crossed by ferries that run to a real timetable — you can miss one. The wilds are crossed on mounts, by glider, and through gateways that connect one named place to the next.',
      'The deck of a ferry is a place you can stand. Ride it and it carries you; step off and the world takes over again.',
    ],
    aside: `${counts.mounts} mounts · ${counts.gateways} gateways · ${counts.vehicles} vessels`,
  },
  {
    kicker: 'The wild',
    title: 'Weather rolls in, and so do the hordes',
    body: [
      'Weather events move across the world on their own clock — aurora, storms, and stranger skies. Some of them stir things up: a horde event scales to the players who answer it, wave after wave, with a real payout at the end.',
      'World bosses keep their own schedule and announce themselves. When one rises, the whole world knows.',
    ],
    aside: `${counts.weather_events} weather events · ${counts.hordes} hordes`,
  },
  {
    kicker: 'Death',
    title: 'Falling means something, and it is recoverable',
    body: [
      'Death is a real state, not a pause. Your body stays where it fell and you come back at a bind point, then walk back for it. What you lose depends on where you fell — the arenas are the one place that takes everything.',
      'There is no punishment so total that it ends your session. There is only a reason to be careful.',
    ],
  },
  {
    kicker: 'Money and making',
    title: 'An economy you can work in',
    body: [
      'Coin buys gear, mounts, and passage. Crafting turns gathered resources into potions, gear, and the odd impossible accessory — each recipe has real ingredients and, sometimes, a real chance to fail.',
      'Beyond coin there are the rarer currencies: standing with a faction, favor at a harbor, and the Concord Sigils you can only ever earn.',
    ],
    aside: `${counts.recipes} recipes · ${counts.resources} resources · ${counts.currencies} currencies`,
  },
  {
    kicker: 'Player against player',
    title: 'Arenas with rules, not an open season',
    body: [
      'Most of the world is safe. Where PvP is allowed it is declared per zone and stated plainly — some places fight over species, some over faction, and the arenas run free-for-all bouts with full loot on the sand.',
      'You always know the rules of the ground you are standing on before someone tests them.',
    ],
    aside: `${counts.zones} zones with declared PvP modes`,
  },
  {
    kicker: 'Three worlds',
    title: 'The planet, its moon, and its own depths',
    body: [
      'Synmergia is the surface: the strait, the villages, the roads that start at stones that remember the way home.',
      'The pale stone is the moon — a small world that exists only while someone stands on it, where the builders come and go as the sky aligns.',
      'Beneath it all is the Deep Root: the world under the world, reached through its own passages, with a tide and a glow all its own.',
    ],
  },
];

export default function ExperiencesPage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <Link
        to="/"
        className="inline-flex items-center gap-1.5 text-xs text-ink-soft hover:text-accent transition-colors mb-6"
      >
        <ArrowLeft className="w-3.5 h-3.5" /> Home
      </Link>

      <header className="mb-12">
        <p className="text-[11px] tracking-[0.3em] uppercase text-accent/80 mb-3">
          What to expect
        </p>
        <h1 className="font-display text-3xl sm:text-4xl mb-4 leading-tight">
          A world you can learn the rules of
        </h1>
        <p className="text-base text-ink-soft leading-relaxed">
          Synmergia is free to play, runs in your browser, and is a real place with
          real rules — here is what meets you when you step onto the planet, in the
          order you will meet it.
        </p>
      </header>

      <div className="space-y-10">
        {SECTIONS.map((s, i) => (
          <section key={s.title} className="border-t border-line pt-8">
            <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">
              {String(i + 1).padStart(2, '0')} · {s.kicker}
            </p>
            <h2 className="font-display text-xl sm:text-2xl mb-3 leading-snug">{s.title}</h2>
            {s.body.map((p, j) => (
              <p key={j} className="text-sm text-ink-soft leading-relaxed mb-3">
                {p}
              </p>
            ))}
            {s.aside && (
              <p className="text-xs font-mono text-accent/90 mt-1">{s.aside}</p>
            )}
          </section>
        ))}
      </div>

      {/* Honest scope: what it is not (yet). Kept player-facing; the
          build/technical home is the Open Source page. */}
      <section className="mt-12 border-t border-line pt-8">
        <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">
          Honest scope
        </p>
        <h2 className="font-display text-xl sm:text-2xl mb-3">What it is not, yet</h2>
        <p className="text-sm text-ink-soft leading-relaxed mb-3">
          Synmergia is a real, working world — and it is still growing. Some art is
          still placeholder, some systems are early, and there is more to come. We
          would rather tell you that up front than pretend otherwise.
        </p>
        <p className="text-sm text-ink-soft leading-relaxed">
          It is free to play and it is being built in the open, which means you can
          watch it grow and even help shape it. If that sounds like your kind of
          project,{' '}
          <Link to="/opensource" className="text-accent hover:underline">
            come build it with us
          </Link>
          .
        </p>
      </section>

      <div className="mt-12 flex flex-wrap items-center gap-3">
        <Link
          to="/play"
          className="inline-flex items-center gap-2 px-6 py-3 rounded-lg bg-accent text-paper font-semibold hover:bg-accent-deep transition-colors shadow"
        >
          Play in browser <ArrowRight className="w-4 h-4" />
        </Link>
        <Link
          to="/codex"
          className="inline-flex items-center gap-2 px-6 py-3 rounded-lg border border-line text-ink hover:border-accent hover:text-accent transition-colors"
        >
          Browse the Codex
        </Link>
      </div>
    </div>
  );
}
