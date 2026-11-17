import { Link } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';

// Accessibility page — the player-facing side of the accessibility work.
// The technical contract (A11yService, snapshot shape, probe rig) lives in
// the docs portal (/access/human/); this page is what a player gets:
// named controls, real focus, and the settings that change the surface.
// Every claim here is traceable to settings_panel.gd and UIStyles.

const DOCS_HUMAN = 'https://docs.creadev.org/synmergia/access/human/';
const REPO = 'https://github.com/dhaupin/synmergia';

const SETTINGS: { name: string; range: string; changes: string }[] = [
  { name: 'High Contrast Mode', range: 'On / off', changes: 'High-contrast panels and focus styles, checked against a 4.5:1 contrast bar.' },
  { name: 'UI Text Scale', range: '0.8x to 1.5x', changes: 'Scales UI text across the HUD and panels.' },
  { name: 'Reduce Motion', range: 'On / off', changes: 'Disables UI transitions, animations, and particle effects.' },
  { name: 'Colorblind Mode', range: 'On / off + type', changes: 'Applies a color-correction shader (deuteranopia, protanopia, tritanopia).' },
  { name: 'Screen Shake', range: 'On / off', changes: 'Camera shake.' },
  { name: 'Flash Effects', range: 'On / off', changes: 'Critical and damage flashes.' },
];

const PROMISES = [
  'Every interactive control has a name and a stated consequence.',
  'Controls take focus, and focus is visible.',
  'State is communicated as text, not color alone.',
  'Actions route through the real game verb, never a side channel.',
  'High contrast, text scale, and reduce motion are respected.',
];

export default function AccessibilityPage() {
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
          Accessibility
        </p>
        <h1 className="font-display text-3xl sm:text-4xl mb-4 leading-tight">
          The world, reachable
        </h1>
        <p className="text-base text-ink-soft leading-relaxed">
          The interface is built from the controls themselves. A screen reader, a
          switch user, and a keyboard-only player all read the same named nodes and
          walk the same focus order — the menus, the world entities, and the
          actions they offer. Nothing is stored in a side table; the accessibility
          tree is the live scene.
        </p>
      </header>

      <section className="mb-12">
        <h2 className="font-display text-xl mb-4">Settings that change the surface</h2>
        <p className="text-sm text-ink-soft leading-relaxed mb-4">
          These are the labels you see in the Settings panel. Each one changes the
          real surface, not a cosmetic copy.
        </p>
        <div className="overflow-x-auto">
          <table className="w-full text-sm border-collapse">
            <thead>
              <tr className="text-left border-b border-line">
                <th className="py-2 pr-4 font-semibold">Setting</th>
                <th className="py-2 pr-4 font-semibold">Range</th>
                <th className="py-2 font-semibold">What it changes</th>
              </tr>
            </thead>
            <tbody>
              {SETTINGS.map((s) => (
                <tr key={s.name} className="border-b border-line/60 align-top">
                  <td className="py-2.5 pr-4 text-ink whitespace-nowrap">{s.name}</td>
                  <td className="py-2.5 pr-4 text-ink-soft whitespace-nowrap">{s.range}</td>
                  <td className="py-2.5 text-ink-soft">{s.changes}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mb-12">
        <h2 className="font-display text-xl mb-4">What good looks like</h2>
        <ul className="list-disc pl-5 space-y-1.5 text-sm text-ink-soft leading-relaxed">
          {PROMISES.map((p) => (
            <li key={p}>{p}</li>
          ))}
        </ul>
      </section>

      <section className="mb-12">
        <h2 className="font-display text-xl mb-3">For screen reader and keyboard users</h2>
        <p className="text-sm text-ink-soft leading-relaxed mb-3">
          On desktop, the game exposes native accessibility properties through the
          engine. Keyboard play uses the scene focus order, and the menus route Tab
          through one shared service so the order is consistent. On the web, the
          engine's accessibility adapter carries the same tree.
        </p>
        <p className="text-sm text-ink-soft leading-relaxed">
          A secret field reports only that it is set or empty — the value itself
          never leaves the process.
        </p>
      </section>

      <section className="mb-12">
        <h2 className="font-display text-xl mb-3">Where this stands</h2>
        <p className="text-sm text-ink-soft leading-relaxed">
          This page describes the shipped surface; it is not a formal WCAG
          certification, and it does not claim native voice control. The live
          assistive-technology and keyboard pass across the game, the docs, and the
          website is tracked in the open:{' '}
          <a
            href={`${REPO}/issues/101`}
            className="text-accent underline underline-offset-2 hover:text-accent-deep"
          >
            issue #101
          </a>
          .
        </p>
      </section>

      <section className="mb-4">
        <h2 className="font-display text-xl mb-3">Read the contract</h2>
        <p className="text-sm">
          <a href={DOCS_HUMAN} className="text-accent underline underline-offset-2 hover:text-accent-deep">
            Human Accessibility
          </a>{' '}
          <span className="text-ink-soft">
            — the snapshot shape, the focus verbs, the settings table, and the
            probes that verify them, in the docs portal.
          </span>
        </p>
      </section>
    </div>
  );
}
