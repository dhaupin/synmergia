import { Link } from 'react-router-dom';
import { ArrowLeft, ArrowRight } from 'lucide-react';

// Lore page — the story of the world, told in the canon voice of
// labs/prd-story.md and labs/prd-ancient-movers.md. The law of this
// page: no engines, no electronics, no religion, no recorded history.
// Nobody knows what happened; the mystery is the point. The ancients
// (the dormant movers and gates) are spoken of as sleeping, never as
// technology, and their wake-keys are never printed here.

interface Beat {
  kicker: string;
  title: string;
  body: string[];
}

const TIMELINE: Beat[] = [
  {
    kicker: 'Before',
    title: 'The world that hummed',
    body: [
      'Long before anyone kept a record, the land was tended. Not built — tended. Conduit lines ran under the fields, waypoint stones stood at every crossing, and the city-halls of Nexus Central rose in ceramic and alloy. Something moved the cargo, lit the roads, and answered the doors.',
      'People lived at its edges and called it the Convergence. Humans worked its gates and learned its moods. The Akkan clans kept its roads and carved their own ember sigils into its stone. And in its deep halls there were the Synthetics — minds of its own making, who would later have to decide, on their own, what they were.',
    ],
  },
  {
    kicker: 'Then',
    title: 'The Silence',
    body: [
      'And then, in a single season, it all went dark.',
      'No blast. No war. No last message anyone can read. The halls were simply left mid-task — a conduit half-re-wound, a door standing open on a room no one had finished using. Every machine stopped at once, together, for a reason that was never written down.',
      'Nobody knows what happened. That is not a riddle with an answer hiding somewhere in the world. It is the shape of the world: a question the whole planet is standing inside.',
    ],
  },
  {
    kicker: 'After',
    title: 'The Long Sleep',
    body: [
      'Nature did not wait for an explanation. Roots split the ceramic. Moss drank the conduits. Centuries passed, and the forest ate the cities the way water eats a shore — patiently, completely, without malice.',
      'The mycelium that had once served the Convergence kept growing after there was nothing left to serve. Untended and purposeless, it spread through the deep green dark and slowly became something of its own — the Bloom. It is older than any living keeper, and it remembers more of the Convergence than anyone.',
    ],
  },
  {
    kicker: 'Now',
    title: 'The Waking',
    body: [
      'You arrive at the end of all this. Villages like Easthollow stack timber against the hull of something fallen and call it a wall. The first waypoint stones are flickering teal again, the color of a thing that can wake rather than a thing that is awake.',
      'Explorers carry tablets — hand-woken fragments of the old world that answer a touch. And the whole of the game narrows to one verb: find the dormant thing, and wake it.',
    ],
  },
];

const MYSTERIES = [
  {
    title: 'What caused the Silence?',
    body: 'Every hall stopped in the same season, mid-task, with no record of why. The world will not tell you. Nothing will.',
  },
  {
    title: 'Who made the Convergence?',
    body: 'There are no maker-ruins and no maker-bodies anywhere. The Synthetics are proof that something was made — and evidence without an author.',
  },
  {
    title: 'What is the Nexus Core?',
    body: 'The heart of the old network. The quests say reach it. They do not say what will be there when you do.',
  },
  {
    title: 'Why did the Bloom keep growing?',
    body: 'It served the Convergence for longer than anyone. When there was nothing left to serve, it grew anyway. The Collective believes it can still be spoken with.',
  },
  {
    title: 'Why do some things wake only halfway?',
    body: 'The Clockwork Saint wears a split face and a single lit eye. It implies that waking is not all-or-nothing — and that something out there is still, stubbornly, half-awake.',
  },
];

const ANCIENTS = [
  {
    name: 'The ferries',
    state: 'Awake',
    body: 'The boats still run — on a real schedule, from a real dock, and you can miss one. They are the one great machine the world has kept turning, and nobody remembers agreeing to it.',
  },
  {
    name: 'The standing rings',
    state: 'Sleeping',
    body: 'Rings of old alloy stand at the Haven Spire and the Meadow Gate, humming faintly and doing nothing. The elders say the ancients did not build stairs. They built throws. Nobody alive has seen one throw.',
  },
  {
    name: 'The Ascent Thrower',
    state: 'Sleeping',
    body: 'Deep in the Root, a stone ring waits by the climb out — built, they say, to hurl a rider up into the dark where the wings catch the vent. It has never fired. It sleeps until the world decides the mystery moves.',
  },
  {
    name: 'The ruin movers',
    state: 'Unfound',
    body: 'Conduit gliders, islet lifters, caravan crawlers — machines meant to carry whole settlements across the map. They lie somewhere under the moss, unsolved, waiting for someone to work out what wakes them.',
  },
];

export default function LorePage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <Link
        to="/"
        className="inline-flex items-center gap-1.5 text-xs text-ink-soft hover:text-accent transition-colors mb-6"
      >
        <ArrowLeft className="w-3.5 h-3.5" /> Home
      </Link>

      <header className="mb-12">
        <p className="text-[11px] tracking-[0.3em] uppercase text-accent/80 mb-3">The Lore</p>
        <h1 className="font-display text-3xl sm:text-4xl mb-4 leading-tight">
          A world that woke up without its memory
        </h1>
        <p className="text-base text-ink-soft leading-relaxed">
          Synmergia does not have a history. It has a silence where a history should be — and
          everything you meet in it is something that was left running when the lights went out.
        </p>
      </header>

      {/* The story, in four beats */}
      <div className="space-y-10">
        {TIMELINE.map((b, i) => (
          <section key={b.title} className="border-t border-line pt-8">
            <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">
              {String(i + 1).padStart(2, '0')} · {b.kicker}
            </p>
            <h2 className="font-display text-xl sm:text-2xl mb-3 leading-snug">{b.title}</h2>
            {b.body.map((p, j) => (
              <p key={j} className="text-sm text-ink-soft leading-relaxed mb-3">
                {p}
              </p>
            ))}
          </section>
        ))}
      </div>

      {/* The open mysteries */}
      <section className="mt-12 border-t border-line pt-8">
        <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">The Mysteries</p>
        <h2 className="font-display text-xl sm:text-2xl mb-3 leading-snug">
          Questions the world keeps open
        </h2>
        <p className="text-sm text-ink-soft leading-relaxed mb-6">
          Some of these have answers buried in the world, written into its seasons, its
          monuments, and its sky. Some do not have answers at all. The world does not publish
          them, and neither will we — working them out is the point.
        </p>
        <div className="space-y-4">
          {MYSTERIES.map((m) => (
            <div key={m.title} className="rounded-xl border border-line bg-surface p-5">
              <h3 className="font-display text-lg mb-1.5">{m.title}</h3>
              <p className="text-sm text-ink-soft leading-relaxed">{m.body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* The ancients */}
      <section className="mt-12 border-t border-line pt-8">
        <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">The Ancients</p>
        <h2 className="font-display text-xl sm:text-2xl mb-3 leading-snug">
          The machines that were left sleeping
        </h2>
        <p className="text-sm text-ink-soft leading-relaxed mb-6">
          The old world left movers behind — great carriers and rings meant to bear people and
          cargo across the map. Most are dormant, and waking one is never a purchase. It is a
          puzzle, a long road, a patient watch, or a hand laid in the right place at the right
          time. Some keys are held so deep that no one — not even the people who built the
          world — can read them back.
        </p>
        <div className="space-y-4">
          {ANCIENTS.map((a) => (
            <div key={a.name} className="rounded-xl border border-line bg-surface p-5">
              <div className="flex items-baseline justify-between gap-3 mb-1.5">
                <h3 className="font-display text-lg">{a.name}</h3>
                <span className="text-[10px] uppercase tracking-[0.14em] px-2 py-0.5 rounded-full border border-line text-ink-soft shrink-0">
                  {a.state}
                </span>
              </div>
              <p className="text-sm text-ink-soft leading-relaxed">{a.body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Closing */}
      <section className="mt-12 border-t border-line pt-8">
        <p className="text-sm text-ink-soft leading-relaxed">
          There is no prophecy here, and no chosen one. There is a planet that fell asleep
          holding its work, a mycelium that outlived its purpose, three peoples who never
          agreed on what any of it meant — and you, walking into the quiet with a tablet and a
          question. Wake what you can. The world will not explain itself.
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
