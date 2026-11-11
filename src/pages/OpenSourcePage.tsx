import { Link } from 'react-router-dom';
import { ArrowLeft, ArrowRight } from 'lucide-react';

// Open Source page — the home for everything technical. The player pages
// stay in-world and markety; the dev/server/code lingo lives HERE, along
// with the honest reason we opened the source and the call for people who
// want to build. House law: the reason is told straight, not dressed up.

const REPO = 'https://github.com/dhaupin/synmergia';

const CRAFT: { glyph: string; title: string; body: string }[] = [
  {
    glyph: '⌘',
    title: 'Engineers',
    body: 'GDScript and a real authoritative server: combat resolution, an event hub, the frame primitives, and an orchestrator that can run the shard. If systems design and netcode are your craft, the whole engine is in the repo.',
  },
  {
    glyph: '◈',
    title: 'Artists & modelers',
    body: 'Characters, creatures, gear, and the whole look of the world. There is a Blender pipeline in-tree and a long list of placeholders waiting to be made real.',
  },
  {
    glyph: '◧',
    title: 'World builders',
    body: 'Zones, quests, dungeons, and the lore that holds them together. It is all data — resources under game/data — and the Codex is the live read of it.',
  },
  {
    glyph: '⬡',
    title: 'Architects & engineers',
    body: 'The frame: spatial geometry, the state tree, multi-iso orchestration. The parts that let one world scale to many shards, designed in the open.',
  },
  {
    glyph: '⇄',
    title: 'Testers & players',
    body: 'Play it and break it. Reproduce a bug, write a probe, file an issue, or argue about a number. The people who break the world honestly make it stronger.',
  },
  {
    glyph: '✦',
    title: 'Idea people',
    body: 'You do not have to write a line of code. If you have a good idea for a system, a zone, a monster, or a story beat, open an issue and say it out loud.',
  },
];

const STACK = [
  'Godot 4.7.2 — GDScript, browser-first',
  'React 19 + Vite + Tailwind (this site)',
  'Authoritative server + multi-iso orchestrator',
  'Deterministic world generation from one seed',
  'MIT-licensed, built in the open',
];

export default function OpenSourcePage() {
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
          Open Source
        </p>
        <h1 className="font-display text-3xl sm:text-4xl mb-4 leading-tight">
          The whole world is in the open
        </h1>
        <p className="text-base text-ink-soft leading-relaxed">
          Synmergia is free, MIT-licensed, and built in the open. Every system
          that runs the world — the engine, the server, the data, this website —
          is in one public repository, and anyone is welcome to read it, run it,
          or help build it.
        </p>
      </header>

      {/* Why we opened it */}
      <section className="border-t border-line pt-8 mb-12">
        <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">
          Why open source
        </p>
        <h2 className="font-display text-xl sm:text-2xl mb-4 leading-snug">
          Because the alternative is a losing game
        </h2>
        <p className="text-sm text-ink-soft leading-relaxed mb-3">
          Here is the honest version. A game like this will be reverse-engineered.
          People will poke at the server, pull the client apart, hunt for exploits,
          and copy whatever they can. That is not a risk we can wish away by hiding
          the code — closed source just means the people who get in first are the
          ones we never hear from.
        </p>
        <p className="text-sm text-ink-soft leading-relaxed mb-3">
          So we made the call early: open the whole thing. Put every line where
          everyone can see it, and turn the people who would have cracked it in the
          dark into people who can fix it in the light. A bug someone reports is a
          bug we did not have to find. An exploit someone patches is a cheat that
          never reaches live. A stranger who loves the idea can become a builder.
        </p>
        <p className="text-sm text-ink-soft leading-relaxed">
          Teamwork is the whole strategy. You cannot out-hide a determined crowd,
          but you can out-build one — and a community that can read the source is
          the strongest anti-cheat, the best QA, and the fastest roadmap we could
          ask for. Open is not charity. It is the stronger position.
        </p>
      </section>

      {/* Who we are looking for */}
      <section className="border-t border-line pt-8 mb-12">
        <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">
          The Call
        </p>
        <h2 className="font-display text-xl sm:text-2xl mb-3 leading-snug">
          Come build it with us
        </h2>
        <p className="text-sm text-ink-soft leading-relaxed mb-6">
          It takes more than programmers to make a world. If any of these is your
          craft — or your hobby — there is a place for you here.
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {CRAFT.map((c) => (
            <div key={c.title} className="rounded-xl border border-line bg-surface p-5">
              <h3 className="font-display text-lg mb-2">
                <span className="text-accent mr-2" aria-hidden="true">{c.glyph}</span>
                {c.title}
              </h3>
              <p className="text-sm text-ink-soft leading-relaxed">{c.body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* How to start */}
      <section className="border-t border-line pt-8 mb-12">
        <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">
          Get started
        </p>
        <h2 className="font-display text-xl sm:text-2xl mb-4 leading-snug">
          Four ways in
        </h2>
        <ol className="space-y-3 text-sm text-ink-soft leading-relaxed list-decimal pl-5">
          <li>
            <span className="text-ink font-semibold">Play it first.</span> The best
            contribution starts with knowing the world. Play a session, then tell us
            what felt wrong.
          </li>
          <li>
            <span className="text-ink font-semibold">Read the code.</span> Clone the
            repo and get it running locally. The engine project lives in{' '}
            <code className="text-accent/90 font-mono text-xs">game/</code>, the site
            in <code className="text-accent/90 font-mono text-xs">src/</code>, and
            the world&apos;s content in{' '}
            <code className="text-accent/90 font-mono text-xs">game/data/</code>.
          </li>
          <li>
            <span className="text-ink font-semibold">Find your first thread.</span>{' '}
            Issues and open work are public. Pick something small, do it well, and
            open a pull request.
          </li>
          <li>
            <span className="text-ink font-semibold">Or just bring an idea.</span>{' '}
            Open an issue with the thing you would build. The roadmap is written in
            the open, and good ideas change it.
          </li>
        </ol>
      </section>

      {/* The stack — the technical home */}
      <section className="border-t border-line pt-8 mb-12">
        <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">
          Under the hood
        </p>
        <h2 className="font-display text-xl sm:text-2xl mb-4 leading-snug">
          What it is built with
        </h2>
        <ul className="space-y-2">
          {STACK.map((s) => (
            <li key={s} className="flex items-start gap-3 text-sm text-ink-soft leading-relaxed">
              <span className="text-accent mt-0.5" aria-hidden="true">▸</span>
              <span>{s}</span>
            </li>
          ))}
        </ul>
        <p className="text-sm text-ink-soft leading-relaxed mt-4">
          The client runs in the browser, the server is authoritative, and the whole
          world is data-driven — which is why a designer, not only an engineer, can
          add a zone, a quest, or a creature without touching the engine.
        </p>
      </section>

      {/* CTA */}
      <section className="border-t border-line pt-8">
        <h2 className="font-display text-xl sm:text-2xl mb-3 leading-snug">
          Read it, run it, build it
        </h2>
        <p className="text-sm text-ink-soft leading-relaxed mb-6">
          The repository is public, the license is MIT, and the door is open. Come
          see how the world is made — then help make it.
        </p>
        <div className="flex flex-wrap items-center gap-3">
          <a
            href={REPO}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-2 px-6 py-3 rounded-lg bg-accent text-paper font-semibold hover:bg-accent-deep transition-colors shadow"
          >
            View the source <ArrowRight className="w-4 h-4" />
          </a>
          <a
            href={`${REPO}/issues`}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-2 px-6 py-3 rounded-lg border border-line text-ink hover:border-accent hover:text-accent transition-colors"
          >
            Open an issue
          </a>
          <Link
            to="/codex"
            className="inline-flex items-center gap-2 px-6 py-3 rounded-lg border border-line text-ink hover:border-accent hover:text-accent transition-colors"
          >
            Browse the Codex
          </Link>
        </div>
      </section>
    </div>
  );
}
