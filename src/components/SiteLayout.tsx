import { Link, NavLink, Outlet, useLocation } from 'react-router-dom';
import { useEffect, useState } from 'react';
import { Menu, X } from 'lucide-react';

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

const NavItem = ({ to, children }: { to: string; children: React.ReactNode }) => {
  if (to.startsWith('http')) {
    return (
      <a
        href={to}
        target="_blank"
        rel="noopener noreferrer"
        className="px-3 py-1.5 rounded-md text-sm transition-colors text-ink-soft hover:text-ink hover:bg-accent/10"
      >
        {children}
        <span className="sr-only"> (opens in a new tab)</span>
      </a>
    );
  }
  return (
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
};

const DOCS_URL = 'https://docs.creadev.org/synmergia/';

// Primary nav, in reading order. Play leads because it is the one thing a
// first-time visitor came to do; the brand (logo + wordmark) is the home
// link, so "Home" is deliberately absent.
const NAV = [
  { to: '/play', label: 'Play' },
  { to: '/experiences', label: 'Experiences' },
  { to: '/codex', label: 'Codex' },
  { to: '/lore', label: 'Lore' },
  { to: '/rules', label: 'Rules' },
  { to: DOCS_URL, label: 'Docs' },
];

export default function SiteLayout() {
  const pckHash = usePckHash();
  const [menuOpen, setMenuOpen] = useState(false);
  const location = useLocation();

  // Close the mobile menu whenever the route changes.
  useEffect(() => {
    setMenuOpen(false);
  }, [location.pathname]);

  return (
    <div className="min-h-screen flex flex-col">
      <a href="#main" className="skip-link">Skip to content</a>
      <header className="border-b border-line bg-surface/80 backdrop-blur sticky top-0 z-40">
        <div className="max-w-6xl mx-auto px-4 py-3 flex items-center justify-between gap-3">
          <Link to="/" className="flex items-center gap-3 shrink-0" aria-label="Synmergia home">
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

          {/* Desktop nav */}
          <nav className="hidden md:flex items-center gap-1" aria-label="Primary">
            {NAV.map((n) => (
              <NavItem key={n.to} to={n.to}>
                {n.label}
              </NavItem>
            ))}
          </nav>

          {/* Mobile burger */}
          <button
            type="button"
            className="md:hidden inline-flex items-center justify-center w-10 h-10 rounded-md border border-line text-ink-soft hover:text-ink hover:border-accent/60 transition-colors"
            aria-label={menuOpen ? 'Close menu' : 'Open menu'}
            aria-expanded={menuOpen}
            aria-controls="mobile-nav"
            onClick={() => setMenuOpen((v) => !v)}
          >
            {menuOpen ? <X className="w-5 h-5" aria-hidden="true" /> : <Menu className="w-5 h-5" aria-hidden="true" />}
          </button>
        </div>

        {/* Mobile nav panel */}
        {menuOpen && (
          <nav id="mobile-nav" className="md:hidden border-t border-line bg-surface/95" aria-label="Primary">
            <div className="max-w-6xl mx-auto px-4 py-2 flex flex-col">
              {NAV.map((n) =>
                n.to.startsWith('http') ? (
                  <a
                    key={n.to}
                    href={n.to}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="px-3 py-2.5 rounded-md text-sm transition-colors text-ink-soft hover:text-ink hover:bg-accent/5"
                  >
                    {n.label}
                    <span className="sr-only"> (opens in a new tab)</span>
                  </a>
                ) : (
                  <NavLink
                    key={n.to}
                    to={n.to}
                    className={({ isActive }) =>
                      `px-3 py-2.5 rounded-md text-sm transition-colors ${
                        isActive ? 'text-accent bg-accent/10' : 'text-ink-soft hover:text-ink hover:bg-accent/5'
                      }`
                    }
                  >
                    {n.label}
                  </NavLink>
                )
              )}
            </div>
          </nav>
        )}
      </header>

      <main id="main" tabIndex={-1} className="flex-1">
        <Outlet />
      </main>

      <footer className="border-t border-line mt-16">
        <div className="max-w-6xl mx-auto px-4 py-8 text-xs text-ink-soft flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <img
              src="/branding/logo-synmergia-wordmark.png"
              alt="Synmergia"
              className="h-5 w-auto opacity-80"
            />
            <span>
              <a
                href="https://github.com/dhaupin/synmergia"
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-accent"
              >
                Free &amp; open source
              </a>
              {' · '}© {new Date().getFullYear()}{' '}
              <a
                href="https://creadev.org"
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-accent"
              >
                Creadev.org
              </a>
            </span>
          </div>
          <nav className="flex items-center gap-4" aria-label="Footer">
            <Link to="/lore" className="hover:text-accent">Lore</Link>
            <Link to="/rules" className="hover:text-accent">Rules</Link>
            <Link to="/opensource" className="hover:text-accent">Open Source</Link>
            <a href={DOCS_URL} className="hover:text-accent">Docs</a>
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
          </nav>
        </div>
      </footer>
    </div>
  );
}
