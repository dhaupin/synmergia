import React, { useEffect, useState } from 'react';
import { Gamepad2, Server, CheckCircle2, AlertTriangle } from 'lucide-react';

export type PortalMode = 'wasm' | 'admin';

// Pack freshness stamp: the SAME sha256 CI writes to web/game.pck.hash
// for the content-addressed pack URL. Fetching it live (not a build-
// time env) means the header always shows exactly what `web/` serves
// right now, deploy or dev alike -- no staleness, no rebuild needed.
const usePckHash = () => {
  const [hash, setHash] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    fetch('web/game.pck.hash', { cache: 'no-store' })
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

interface PortalHeaderProps {
  currentMode: PortalMode;
  onSelectMode: (mode: PortalMode) => void;
  crossOriginIsolated: boolean;
}

export const PortalHeader: React.FC<PortalHeaderProps> = ({
  currentMode,
  onSelectMode,
  crossOriginIsolated,
}) => {
  const pckHash = usePckHash();
  return (
    <header className="bg-slate-900 border-b border-slate-800 px-4 py-2.5 flex flex-wrap items-center justify-between gap-3 text-white z-40 select-none">
      {/* Brand & Identity */}
      <div className="flex items-center gap-3">
        <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-amber-500 to-amber-700 flex items-center justify-center font-bold text-slate-950 shadow-md">
          S
        </div>
        <div>
          <div className="flex items-center gap-2">
            <h1 className="font-bold tracking-tight text-slate-100 text-sm md:text-base">
              Synmergia <span className="text-amber-400 font-semibold">Web Portal</span>
            </h1>
            <span
              className="text-xs px-2 py-0.5 rounded bg-slate-800 text-amber-300 border border-amber-800/60 font-mono"
              title="sha256 prefix of the packed game.pck currently served — the content-addressed cache key the engine loads"
            >
              {pckHash ? `pck ${pckHash}` : 'pck —'}
            </span>
          </div>
        </div>
      </div>

      {/* Mode Switcher Nav (wasm-first: WASM client + Admin tooling) */}
      <nav className="flex items-center bg-slate-950/80 p-1 rounded-lg border border-slate-800">
        <button
          type="button"
          onClick={() => onSelectMode('wasm')}
          className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
            currentMode === 'wasm'
              ? 'bg-amber-500 text-slate-950 font-semibold shadow-sm'
              : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Gamepad2 className="w-4 h-4" />
          <span>Godot WASM</span>
        </button>

        <button
          type="button"
          onClick={() => onSelectMode('admin')}
          className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
            currentMode === 'admin'
              ? 'bg-amber-500 text-slate-950 font-semibold shadow-sm'
              : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Server className="w-4 h-4" />
          <span>Admin &amp; Ops</span>
        </button>
      </nav>

      {/* Isolation badge: the one load-bearing diagnostic (threads gate) */}
      <div
        title={
          crossOriginIsolated
            ? 'Cross-Origin Isolation active (COOP/COEP enabled, SharedArrayBuffer ready)'
            : 'Cross-Origin Isolation missing: Web Workers / Threads restricted'
        }
        className={`hidden md:flex items-center gap-1.5 px-2.5 py-1 rounded border text-xs ${
          crossOriginIsolated
            ? 'bg-emerald-950/50 border-emerald-800/60 text-emerald-400'
            : 'bg-amber-950/50 border-amber-800/60 text-amber-400'
        }`}
      >
        {crossOriginIsolated ? (
          <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
        ) : (
          <AlertTriangle className="w-3.5 h-3.5 text-amber-400" />
        )}
        <span>{crossOriginIsolated ? 'WASM Isolated' : 'Non-Isolated'}</span>
      </div>
    </header>
  );
};
