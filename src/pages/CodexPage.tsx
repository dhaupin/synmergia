import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Search, BookOpen, ArrowLeft } from 'lucide-react';

import { buildCodex, CODEX_TOTAL, type CodexEntry } from '../lib/codex';

// The Codex: a browsable read of the world's data files. Everything
// here comes from src/data/godot_data.json, which the build regenerates
// from game/data/**/*.tres (scripts/sync_godot_data.ts) -- so the page
// can never claim a class, skill, or item the game does not ship. The
// counts on the lander and the entries here share that one source.

const Tag = ({ children }: { children: React.ReactNode }) => (
  <span className="text-[10px] uppercase tracking-[0.14em] px-2 py-0.5 rounded-full border border-line text-ink-soft">
    {children}
  </span>
);

function EntryDetail({ entry, categoryLabel }: { entry: CodexEntry; categoryLabel: string }) {
  return (
    <article className="rounded-xl border border-line bg-surface p-6">
      <p className="text-[11px] uppercase tracking-[0.24em] text-accent/80 mb-2">{categoryLabel}</p>
      <h2 className="font-display text-2xl text-ink leading-tight">{entry.name}</h2>
      {entry.tags.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-2">
          {entry.tags.map((t) => (
            <Tag key={t}>{t}</Tag>
          ))}
        </div>
      )}
      {entry.description && (
        <p className="mt-4 text-sm text-ink-soft leading-relaxed">{entry.description}</p>
      )}
      {entry.facts.length > 0 && (
        <dl className="mt-6 grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
          {entry.facts.map((f) => (
            <div key={f.label} className="border-t border-line pt-2">
              <dt className="text-[11px] uppercase tracking-[0.14em] text-ink-soft">{f.label}</dt>
              <dd className="text-sm text-ink mt-0.5">{f.value}</dd>
            </div>
          ))}
        </dl>
      )}
      <p className="mt-6 text-[11px] text-ink-soft font-mono break-all">{entry.id}</p>
    </article>
  );
}

export default function CodexPage() {
  const categories = useMemo(() => buildCodex(), []);
  const [catKey, setCatKey] = useState(categories[0]?.key ?? '');
  const [query, setQuery] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const activeCat = categories.find((c) => c.key === catKey) ?? categories[0];

  const filtered = useMemo(() => {
    if (!activeCat) return [];
    const q = query.trim().toLowerCase();
    if (!q) return activeCat.entries;
    return activeCat.entries.filter((e) => e.search.includes(q));
  }, [activeCat, query]);

  const selected =
    filtered.find((e) => e.id === selectedId) ?? filtered[0] ?? null;

  const selectCategory = (key: string) => {
    setCatKey(key);
    setQuery('');
    setSelectedId(null);
  };

  return (
    <div className="max-w-6xl mx-auto px-4 py-12">
      <Link
        to="/"
        className="inline-flex items-center gap-1.5 text-xs text-ink-soft hover:text-accent transition-colors mb-6"
      >
        <ArrowLeft className="w-3.5 h-3.5" /> Home
      </Link>

      <header className="mb-8">
        <p className="text-[11px] tracking-[0.3em] uppercase text-accent/80 mb-3">The Codex</p>
        <h1 className="font-display text-3xl sm:text-4xl mb-3">Everything the world is made of</h1>
        <p className="text-sm text-ink-soft max-w-2xl leading-relaxed">
          Classes, skills, species, enemies, items, recipes, mounts, the sky, and the hordes
          — read straight from the same data files the server loads.{' '}
          <span className="text-ink">{CODEX_TOTAL.toLocaleString()} entries</span> across{' '}
          {categories.length} categories. Nothing here is aspirational; it is what ships.
        </p>
      </header>

      {/* Category rail */}
      <div className="flex flex-wrap gap-2 mb-6">
        {categories.map((c) => {
          const active = c.key === activeCat?.key;
          return (
            <button
              key={c.key}
              onClick={() => selectCategory(c.key)}
              className={`text-xs px-3 py-1.5 rounded-full border transition-colors ${
                active
                  ? 'border-accent text-accent bg-accent/10'
                  : 'border-line text-ink-soft hover:border-accent/60 hover:text-ink'
              }`}
            >
              {c.label}
              <span className="ml-1.5 text-[10px] opacity-60">{c.entries.length}</span>
            </button>
          );
        })}
      </div>

      {activeCat && (
        <p className="text-xs text-ink-soft mb-6 max-w-2xl">{activeCat.blurb}</p>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] gap-6">
        {/* List column */}
        <div>
          <div className="relative mb-3">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-soft" />
            <input
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={`Search ${activeCat?.label.toLowerCase() ?? ''}…`}
              className="w-full rounded-lg border border-line bg-surface pl-9 pr-3 py-2 text-sm text-ink placeholder:text-ink-soft/70 focus:border-accent focus:outline-none"
            />
          </div>
          <div className="rounded-xl border border-line bg-surface/60 overflow-hidden">
            <ul className="max-h-[32rem] overflow-y-auto divide-y divide-line">
              {filtered.length === 0 && (
                <li className="px-4 py-6 text-sm text-ink-soft text-center">
                  Nothing matches “{query}”.
                </li>
              )}
              {filtered.map((e) => {
                const active = selected?.id === e.id;
                return (
                  <li key={e.id}>
                    <button
                      onClick={() => setSelectedId(e.id)}
                      className={`w-full text-left px-4 py-2.5 transition-colors ${
                        active ? 'bg-accent/10' : 'hover:bg-accent/5'
                      }`}
                    >
                      <span className={`text-sm ${active ? 'text-accent' : 'text-ink'}`}>
                        {e.name}
                      </span>
                      {e.tags.length > 0 && (
                        <span className="ml-2 text-[10px] text-ink-soft">{e.tags[0]}</span>
                      )}
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
          <p className="mt-2 text-[11px] text-ink-soft">
            {filtered.length} {filtered.length === 1 ? 'entry' : 'entries'}
          </p>
        </div>

        {/* Detail column */}
        <div>
          {selected ? (
            <EntryDetail entry={selected} categoryLabel={activeCat?.label ?? ''} />
          ) : (
            <div className="rounded-xl border border-line bg-surface p-8 text-center text-ink-soft">
              <BookOpen className="w-8 h-8 mx-auto mb-3 opacity-50" />
              <p className="text-sm">Pick an entry to read it.</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
