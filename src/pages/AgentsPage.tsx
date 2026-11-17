import { Link } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';

// Agents page — the player-facing side of the AgentDoor. The technical
// contract lives in the docs portal (/access/agents/); this page is what
// it means to a player: agents are players with their own characters, on
// the same verbs, opt-in and off by default. Every claim here is traceable
// to game/core/services/agent_driver.gd and the gamestruct wire.

const DOCS_AGENTS = 'https://docs.creadev.org/synmergia/access/agents/';
const REPO = 'https://github.com/dhaupin/synmergia';

const SHAPE: { glyph: string; title: string; body: string }[] = [
  {
    glyph: '◈',
    title: 'A player, not a backdoor',
    body: 'An agent belongs to exactly one account and has its own character. It parties with humans, levels, fights, and trades. It cannot drive your body or reach into your account — there is no verb for that.',
  },
  {
    glyph: '⌘',
    title: 'The same verbs you use',
    body: 'An agent acts through the real game actions, not a side channel. It reads named controls and world entities, then activates them the same way a keyboard press would. What it can do is what a player can do.',
  },
  {
    glyph: '⛨',
    title: 'Consequential acts wait for a human',
    body: 'Spending, trading, purchasing, dropping, destroying, and selling can park for explicit human approval. A gated verb does not quietly execute — it asks first.',
  },
  {
    glyph: '◧',
    title: 'Off until you turn it on',
    body: 'The door is disabled unless the runtime enables it (SYN_AGENT=1 on a server you run, or the bridge in a web build). It is not bound when it is off, and a non-local bind without a token is refused.',
  },
];

export default function AgentsPage() {
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
          Agents
        </p>
        <h1 className="font-display text-3xl sm:text-4xl mb-4 leading-tight">
          Play alongside agents
        </h1>
        <p className="text-base text-ink-soft leading-relaxed">
          Synmergia is built so a program can join the world as a player — with
          its own character, on the same actions everyone else uses. Agents are
          not a separate mode or a hidden admin path. They are bodies in the same
          world, held to the same rules, and off until someone chooses to run one.
        </p>
      </header>

      <section className="mb-12">
        <h2 className="font-display text-xl mb-4">What an agent is</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {SHAPE.map((s) => (
            <div key={s.title} className="rounded-xl border border-line bg-surface p-5">
              <h3 className="font-display text-base mb-2">
                <span className="text-accent mr-2" aria-hidden="true">{s.glyph}</span>
                {s.title}
              </h3>
              <p className="text-sm text-ink-soft leading-relaxed">{s.body}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mb-12">
        <h2 className="font-display text-xl mb-3">How it works</h2>
        <p className="text-sm text-ink-soft leading-relaxed mb-4">
          An agent observes the current state through named handles — the same
          names a screen reader and a keyboard player read — then acts by handle
          through the real game verb. It can wait for a condition instead of
          sleeping, and it can read what changed since a point in time. When it
          cannot do something, it refuses honestly and says why.
        </p>
        <p className="text-sm text-ink-soft leading-relaxed">
          The generic tool protocol (MCP) is a projection built on top of that
          wire, owned by the separate{' '}
          <span className="text-ink">gamestruct</span> project — not reimplemented
          in the game. If you want to build an agent, the full contract, the local
          door, and the browser companion are documented in the docs portal.
        </p>
      </section>

      <section className="mb-12">
        <h2 className="font-display text-xl mb-3">The honest boundaries</h2>
        <ul className="list-disc pl-5 space-y-1.5 text-sm text-ink-soft leading-relaxed">
          <li>
            <strong className="text-ink">Own character.</strong> An agent cannot
            drive a human's body, and a caller cannot silently address a human
            instead of an agent — an unknown principal is refused by name.
          </li>
          <li>
            <strong className="text-ink">No pixel truth.</strong> When an agent
            asks to see, it gets a descriptor to read with its own vision, not a
            stream of screen pixels. A surface with no renderer says so.
          </li>
          <li>
            <strong className="text-ink">Fail closed.</strong> When a token is
            required, every route demands it; a remote bind without one is
            refused rather than left open.
          </li>
          <li>
            <strong className="text-ink">Same rules.</strong> Agents play under
            the same <Link to="/rules" className="text-accent hover:underline">Rules of the World</Link>{' '}
            as everyone else.
          </li>
        </ul>
      </section>

      <section className="mb-12">
        <h2 className="font-display text-xl mb-3">Read the contract</h2>
        <div className="space-y-2 text-sm">
          <p>
            <a href={DOCS_AGENTS} className="text-accent hover:underline">
              Agent Access
            </a>{' '}
            <span className="text-ink-soft">
              — the door, the routes, the wire, and the verification.
            </span>
          </p>
          <p>
            <a
              href={`${REPO}/blob/main/labs/prd-agent-play.md`}
              className="text-accent hover:underline"
            >
              Agent Play (design)
            </a>{' '}
            <span className="text-ink-soft">— the full design in the repository.</span>
          </p>
          <p>
            <a href={`${REPO}`} className="text-accent hover:underline">
              The source
            </a>{' '}
            <span className="text-ink-soft">
              — the door and the driver are in the open repository.
            </span>
          </p>
        </div>
      </section>
    </div>
  );
}
