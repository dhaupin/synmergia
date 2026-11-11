import { Link, NavLink, Outlet } from 'react-router-dom';
import { useEffect, useState } from 'react';

// Pack-freshness chip: same live sha256 CI writes to web/game.pck.hash
// (the content-addressed cache key the engine loads on /game). Shared
// probe so the lander and the header never disagree with the engine.
export const usePckHash = (): string | null => {
  const [hash, setHash] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    fetch('game/game.pck.hash', { cache: 'no-store' })
      .then((r) => (r.ok ? r.text() : Promise.reject(new Error('no hash'))))
      .then((h) => {
        if (alive) setHash(h.trim().slice(0, 7));
      })
      .catch(() => {
        if (alive) setHash(null);
      });
    return () => {
      alive = false;
    };
  }, []);
  return hash;
};

const NavItem = ({ to, children }: { to: string; children: React.ReactNode }) => (
  <NavLink
    to={to}
    className={({ isActive }) =>
      `px-3 py-1.5 rounded-md text-sm transition-colors hover:bg-accent/10 ${
        isActive ? 'text-accent' : 'text-ink-soft hover:text-ink'
      }`
    }
  >
    {children}
  </NavLink>
);

export default function SiteLayout() {
  const pckHash = usePckHash();
  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b border-line bg-surface/80 backdrop-blur sticky top-0 z-40">
        <div className="max-w-6xl mx-auto px-4 py-3 flex flex-wrap items-center justify-between gap-y-2 gap-x-3">
          <Link to="/" className="flex items-center gap-3 shrink-0">
            <img
              src="/branding/logo-synmergia-emblem-small.png"
              alt=""
              width={32}
              height={26}
              className="h-7 w-auto"
            />
            <span className="font-display font-bold text-lg tracking-tight">Synmergia</span>
            {pckHash && (
              <span
                className="hidden sm:inline text-[10px] px-1.5 py-0.5 rounded bg-surface text-accent border border-line font-mono"
                title="sha256 prefix of the packed game.pck the engine loads"
              >
                {pckHash}
              </span>
            )}
          </Link>
          <nav className="flex flex-wrap items-center gap-1">
            <NavItem to="/">Home</NavItem>
            <NavItem to="/experiences">Experiences</NavItem>
            <NavItem to="/codex">Codex</NavItem>
            <NavItem to="/play">Play</NavItem>
          </nav>
        </div>
      </header>

      <main className="flex-1">
        <Outlet />
      </main>

      <footer className="border-t border-line mt-16">
        <div className="max-w-6xl mx-auto px-4 py-8 text-xs text-ink-soft flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <img
              src="/branding/logo-synmergia-wordmark.png"
              alt="Synmergia"
              className="h-5 w-auto opacity-80"
            />
            <span>© 2026 dhaupin · Synmergia is free and open source (game code) · site {new Date().getFullYear()}</span>
          </div>
          <div className="flex items-center gap-4">
            <Link to="/rules" className="hover:text-accent">Rules</Link>
            <Link to="/privacy" className="hover:text-accent">Privacy</Link>
            <Link to="/terms" className="hover:text-accent">Terms</Link>
            <a
              href="https://github.com/dhaupin/synmergia"
              target="_blank"
              rel="noreferrer"
              className="hover:text-accent"
            >
              GitHub
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}
