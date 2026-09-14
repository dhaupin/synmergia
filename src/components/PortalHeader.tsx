import React from 'react';
import {
  Gamepad2,
  Server,
  ShieldAlert,
  Layers,
  Activity,
  CheckCircle2,
  AlertTriangle,
  RefreshCw,
  Cpu,
} from 'lucide-react';

export type PortalMode = 'wasm' | 'companion' | 'admin';

interface PortalHeaderProps {
  currentMode: PortalMode;
  onSelectMode: (mode: PortalMode) => void;
  crossOriginIsolated: boolean;
  activePlayerCount?: number;
  serverTickRate?: number;
}

export const PortalHeader: React.FC<PortalHeaderProps> = ({
  currentMode,
  onSelectMode,
  crossOriginIsolated,
  activePlayerCount = 42,
  serverTickRate = 20,
}) => {
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
            <span className="text-xs px-2 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700">
              v4.7.2
            </span>
          </div>
          <p className="text-[11px] text-slate-400 hidden sm:block">
            Authoritative MMORPG Architecture · Multi-Iso Orchestrator
          </p>
        </div>
      </div>

      {/* Mode Switcher Nav */}
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
          onClick={() => onSelectMode('companion')}
          className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
            currentMode === 'companion'
              ? 'bg-amber-500 text-slate-950 font-semibold shadow-sm'
              : 'text-slate-300 hover:text-white hover:bg-slate-800/60'
          }`}
        >
          <Layers className="w-4 h-4" />
          <span>2D Companion</span>
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
          <span>Admin & Ops</span>
        </button>
      </nav>

      {/* System Telemetry Badges */}
      <div className="flex items-center gap-2 text-xs">
        {/* Isolation Header Badge */}
        <div
          title={
            crossOriginIsolated
              ? 'Cross-Origin Isolation active (COOP/COEP enabled, SharedArrayBuffer ready)'
              : 'Cross-Origin Isolation missing: Web Workers / Threads restricted'
          }
          className={`hidden md:flex items-center gap-1.5 px-2.5 py-1 rounded border ${
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

        {/* Tick Rate & Concurrency */}
        <div className="flex items-center gap-2 bg-slate-800/70 border border-slate-700/60 px-2.5 py-1 rounded text-slate-300">
          <span className="flex items-center gap-1 text-emerald-400">
            <Activity className="w-3.5 h-3.5 animate-pulse" />
            <span className="font-mono font-medium">{serverTickRate}Hz</span>
          </span>
          <span className="text-slate-500">|</span>
          <span className="text-slate-300 font-mono">{activePlayerCount} peers</span>
        </div>
      </div>
    </header>
  );
};
