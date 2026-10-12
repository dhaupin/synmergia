import React, { useState, useEffect, useRef } from 'react';
import {
  Maximize2,
  Minimize2,
  RotateCw,
  Settings2,
  HardDrive,
  Cpu,
  Info,
  Terminal,
  ExternalLink,
  ShieldCheck,
  AlertCircle,
} from 'lucide-react';

interface GodotClientViewProps {
  onSwitchToCompanion: () => void;
}

export const GodotClientView: React.FC<GodotClientViewProps> = ({ onSwitchToCompanion }) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [showConfig, setShowConfig] = useState(false);
  const [memoryMb, setMemoryMb] = useState<number>(256);
  const [debugMode, setDebugMode] = useState<boolean>(false);
  const [pckStatus, setPckStatus] = useState<'checking' | 'present' | 'missing'>('checking');
  const [shellStatus, setShellStatus] = useState<'checking' | 'present' | 'missing'>('checking');
  const [wasmStatus, setWasmStatus] = useState<'checking' | 'present' | 'missing'>('checking');
  const [crossOriginIsolated, setCrossOriginIsolated] = useState<boolean>(false);

  useEffect(() => {
    setCrossOriginIsolated(typeof window !== 'undefined' && Boolean(window.crossOriginIsolated));

    // Probe ALL THREE halves of the WASM client: the exported shell
    // (web/index.html + game.js), the resource pack, and the engine
    // binary itself. game.wasm is the one CI never commits (artifact-
    // only), so probing it is what turns "blank pane with green chips"
    // into an honest diagnosis.
    fetch('/web/index.html', { method: 'HEAD' })
      .then((res) => setShellStatus(res.ok ? 'present' : 'missing'))
      .catch(() => setShellStatus('missing'));
    fetch('/web/game.pck', { method: 'HEAD' })
      .then((res) => {
        if (res.ok) {
          setPckStatus('present');
        } else {
          setPckStatus('missing');
        }
      })
      .catch(() => setPckStatus('missing'));
    fetch('/web/game.wasm', { method: 'HEAD' })
      .then((res) => setWasmStatus(res.ok ? 'present' : 'missing'))
      .catch(() => setWasmStatus('missing'));
  }, []);

  // Keyboard focus: the iframe does not receive key events until
  // clicked. Focus it on mount (and after reload) so WASD/input works
  // immediately -- the #1 confusion with embedded Godot clients.
  useEffect(() => {
    if (iframeRef.current) {
      iframeRef.current.focus();
    }
  }, [shellStatus]);

  // Reload with a one-time cache-buster: browsers may hold the shell
  // (and the pack it fetches) for a session, and a stale pack silently
  // reverts game fixes. The ?t= forces the iframe to refetch the shell;
  // the shell's own assets are same-origin relative fetches, which the
  // no-cache header on the dev/preview server keeps honest.
  const handleReload = () => {
    if (iframeRef.current) {
      iframeRef.current.src = `/web/index.html?t=${Date.now()}`;
    }
  };

  const handleToggleFullscreen = () => {
    if (!containerRef.current) return;
    if (!document.fullscreenElement) {
      containerRef.current.requestFullscreen().then(() => setIsFullscreen(true)).catch(() => {});
    } else {
      document.exitFullscreen().then(() => setIsFullscreen(false)).catch(() => {});
    }
  };

  return (
    <div ref={containerRef} className="flex-1 flex flex-col bg-slate-950 text-slate-100 overflow-hidden relative">
      {/* Client Control Toolbar */}
      <div className="bg-slate-900/90 border-b border-slate-800 px-4 py-2 flex flex-wrap items-center justify-between gap-3 text-xs">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <span className="font-semibold text-slate-200">Godot 4.7.2 WASM Shell</span>
            <span
              className={`px-2 py-0.5 rounded text-[10px] font-medium border ${
                pckStatus === 'present'
                  ? 'bg-emerald-950/60 border-emerald-800 text-emerald-400'
                  : pckStatus === 'missing'
                  ? 'bg-amber-950/60 border-amber-800 text-amber-400'
                  : 'bg-slate-800 border-slate-700 text-slate-400'
              }`}
            >
              {pckStatus === 'present'
                ? 'game.pck Found'
                : pckStatus === 'missing'
                ? 'game.pck Pending Export'
                : 'Probing...'}
            </span>
          </div>

          <div className="hidden sm:flex items-center gap-1.5 text-slate-400 text-[11px]">
            <Cpu className="w-3.5 h-3.5" />
            <span>Shell: {shellStatus === 'present' ? 'ready' : shellStatus === 'missing' ? 'absent' : 'probing'}</span>
            <span
              className={`px-2 py-0.5 rounded text-[10px] font-medium border ${
                wasmStatus === 'present'
                  ? 'bg-emerald-950/60 border-emerald-800 text-emerald-400'
                  : wasmStatus === 'missing'
                  ? 'bg-rose-950/60 border-rose-800 text-rose-400'
                  : 'bg-slate-800 border-slate-700 text-slate-400'
              }`}
            >
              {wasmStatus === 'present'
                ? 'Engine: game.wasm Ready'
                : wasmStatus === 'missing'
                ? 'Engine: game.wasm Missing'
                : 'Engine: Probing...'}
            </span>
            {debugMode && <span className="text-amber-400 font-mono">[DEBUG]</span>}
          </div>
        </div>

        <div className="flex items-center gap-2">
          {/* Settings / Config Button */}
          <button
            type="button"
            onClick={() => setShowConfig(!showConfig)}
            className="flex items-center gap-1 px-2.5 py-1 rounded bg-slate-800 hover:bg-slate-700 text-slate-300 transition-colors"
            title="Engine Settings"
          >
            <Settings2 className="w-3.5 h-3.5" />
            <span>Options</span>
          </button>

          {/* Reload Button */}
          <button
            type="button"
            onClick={handleReload}
            className="flex items-center gap-1 px-2.5 py-1 rounded bg-slate-800 hover:bg-slate-700 text-slate-300 transition-colors"
            title="Restart WASM Engine"
          >
            <RotateCw className="w-3.5 h-3.5" />
            <span>Reload</span>
          </button>

          {/* Fullscreen Button */}
          <button
            type="button"
            onClick={handleToggleFullscreen}
            className="flex items-center gap-1 px-2.5 py-1 rounded bg-amber-600/80 hover:bg-amber-600 text-slate-950 font-medium transition-colors"
            title="Toggle Fullscreen"
          >
            {isFullscreen ? <Minimize2 className="w-3.5 h-3.5" /> : <Maximize2 className="w-3.5 h-3.5" />}
            <span className="hidden sm:inline">{isFullscreen ? 'Exit' : 'Fullscreen'}</span>
          </button>
        </div>
      </div>

      {/* Options Panel Drawer */}
      {showConfig && (
        <div className="bg-slate-900 border-b border-slate-800 p-4 text-xs grid grid-cols-1 md:grid-cols-3 gap-4 shadow-lg animate-in slide-in-from-top-2 duration-150">
          <div>
            <label className="block text-slate-400 font-medium mb-1">Memory Preference</label>
            <select
              value={memoryMb}
              onChange={(e) => setMemoryMb(Number(e.target.value))}
              disabled
              title="Locked by design: the exported engine fixes its initial WASM heap at build time (baked into game.wasm). The heap still GROWS at runtime as needed -- this only sets the starting floor, so the locked value is not a cap."
              className="w-full bg-slate-800/60 border border-slate-700 rounded px-2 py-1 text-slate-400 cursor-not-allowed"
            >
              <option value={256}>256 MB (exported shell default)</option>
              <option value={128}>128 MB (Lite)</option>
              <option value={512}>512 MB (High Density)</option>
              <option value={1024}>1024 MB (Max / Ultra)</option>
            </select>
            {/* The lock's explanation lives in the DRAWER (not just the
                tooltip): mobile taps never show tooltips, so the select
                read as broken. Show the value + why it is locked. */}
            <p className="text-[10px] text-slate-500 mt-1">
              Locked at {memoryMb} MB -- the exported engine fixes its initial heap
              at build time (baked into game.wasm). The heap still grows at
              runtime as needed; re-export with a different memory budget to
              change the floor.
            </p>
          </div>

          <div>
            <label className="block text-slate-400 font-medium mb-1">Diagnostics</label>
            <label className="flex items-center gap-2 cursor-pointer mt-1.5 text-slate-300">
              <input
                type="checkbox"
                checked={debugMode}
                onChange={(e) => setDebugMode(e.target.checked)}
                className="rounded border-slate-700 text-amber-500 focus:ring-0"
              />
              <span>Verbose Engine Console Output</span>
            </label>
            <p className="text-[10px] text-slate-500 mt-1">Toggles shell debug labeling; engine logs stream to browser DevTools regardless.</p>
          </div>

          <div>
            <label className="block text-slate-400 font-medium mb-1">Device Permission Prompt</label>
            <p className="text-[10px] text-slate-500 mt-1 leading-relaxed">
              On Android browsers the game surface may ask to "access other apps and services on this
              device" — that is the browser's standard <span className="text-slate-300">local-network/loopback</span> consent,
              not something custom. Synmergia plays fine with it <span className="text-amber-300">Blocked</span>;&nbsp;
              only <span className="text-slate-300">Allow</span> if you deliberately run the local 2D companion on this device.
            </p>
          </div>

          <div>
            <label className="block text-slate-400 font-medium mb-1">Cross-Origin Isolation</label>
            <div className="flex items-center gap-2 mt-1">
              <span
                className={`inline-block w-2.5 h-2.5 rounded-full ${
                  crossOriginIsolated ? 'bg-emerald-400' : 'bg-amber-400'
                }`}
              />
              <span className="text-slate-300">
                {crossOriginIsolated ? 'COOP/COEP Headers Active' : 'Headers Pending'}
              </span>
            </div>
            <p className="text-[10px] text-slate-500 mt-1">
              Required for Godot 4 SharedArrayBuffer multi-threading.
            </p>
          </div>
        </div>
      )}

      {/* Main Canvas / IFrame Viewport */}
      <div className="flex-1 relative bg-black flex items-center justify-center">
        <iframe
          ref={iframeRef}
          src="/web/index.html"
          title="Synmergia Godot Web Client"
          className="w-full h-full border-0 absolute inset-0"
          allow="cross-origin-isolated; autoplay; fullscreen; gamepad"
        />

        {/* Notice Overlay if the WASM client cannot run */}
        {shellStatus === 'missing' && (
          <div className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm flex flex-col items-center justify-center p-6 text-center z-20 pointer-events-auto">
            <div className="max-w-lg bg-slate-900 border border-slate-800 rounded-xl p-6 shadow-2xl">
              <div className="w-12 h-12 rounded-full bg-rose-950/80 border border-rose-800/80 flex items-center justify-center mx-auto mb-4 text-rose-400">
                <AlertCircle className="w-6 h-6" />
              </div>
              <h3 className="text-lg font-bold text-slate-100 mb-2">Godot Web Shell Not Deployed</h3>
              <p className="text-xs text-slate-300 leading-relaxed mb-4">
                The <code className="bg-slate-800 px-1 py-0.5 rounded text-amber-300">web/</code> client directory (engine shell) is
                missing from this deployment. The build should copy it to <code className="bg-slate-800 px-1 py-0.5 rounded text-amber-300">dist/web/</code> automatically.
              </p>
              <button
                type="button"
                onClick={handleReload}
                className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-xs transition-colors"
              >
                Check Again
              </button>
            </div>
          </div>
        )}
        {shellStatus === 'present' && pckStatus === 'missing' && (
          <div className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm flex flex-col items-center justify-center p-6 text-center z-20 pointer-events-auto">
            <div className="max-w-lg bg-slate-900 border border-slate-800 rounded-xl p-6 shadow-2xl">
              <div className="w-12 h-12 rounded-full bg-amber-950/80 border border-amber-800/80 flex items-center justify-center mx-auto mb-4 text-amber-400">
                <AlertCircle className="w-6 h-6" />
              </div>
              <h3 className="text-lg font-bold text-slate-100 mb-2">
                Godot Resource Pack (game.pck) Awaiting Export
              </h3>
              <p className="text-xs text-slate-300 leading-relaxed mb-4">
                The Godot WASM runtime container is ready with Cross-Origin Isolation headers active.
                To load the 3D/WASM engine, export the game resources into <code className="bg-slate-800 px-1 py-0.5 rounded text-amber-300">web/game.pck</code>.
              </p>

              <div className="bg-slate-950 rounded-lg p-3 text-left font-mono text-xs text-slate-300 border border-slate-800 mb-4 overflow-x-auto">
                <div className="text-slate-500 mb-1"># Zero-waste local packaging (Strategy 2):</div>
                <div className="text-amber-400">./scripts/pack_web.sh</div>
                <div className="text-slate-500 mt-1"># Or via Godot CLI:</div>
                <div className="text-slate-400">cd game &amp;&amp; godot --headless --export-pack "Web" ../web/game.pck</div>
              </div>

              <div className="flex flex-wrap items-center justify-center gap-3">
                <button
                  type="button"
                  onClick={onSwitchToCompanion}
                  className="px-4 py-2 bg-amber-500 hover:bg-amber-600 text-slate-950 font-semibold rounded-lg text-xs transition-colors flex items-center gap-1.5"
                >
                  <span>Launch 2D Companion Client</span>
                  <ExternalLink className="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  onClick={handleReload}
                  className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-xs transition-colors"
                >
                  Check Again
                </button>
              </div>
            </div>
          </div>
        )}
        {shellStatus === 'present' && pckStatus === 'present' && wasmStatus === 'missing' && (
          <div className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm flex flex-col items-center justify-center p-6 text-center z-20 pointer-events-auto">
            <div className="max-w-lg bg-slate-900 border border-slate-800 rounded-xl p-6 shadow-2xl">
              <div className="w-12 h-12 rounded-full bg-rose-950/80 border border-rose-800/80 flex items-center justify-center mx-auto mb-4 text-rose-400">
                <AlertCircle className="w-6 h-6" />
              </div>
              <h3 className="text-lg font-bold text-slate-100 mb-2">
                Engine Binary (game.wasm) Missing
              </h3>
              <p className="text-xs text-slate-300 leading-relaxed mb-4">
                The shell and resource pack are present, but the compiled engine
                (<code className="bg-slate-800 px-1 py-0.5 rounded text-amber-300">web/game.wasm</code>) is not -- CI ships it as
                an artifact only, so a full export must be run locally. This is what a blank pane means.
              </p>

              <div className="bg-slate-950 rounded-lg p-3 text-left font-mono text-xs text-slate-300 border border-slate-800 mb-4 overflow-x-auto">
                <div className="text-slate-500 mb-1"># Full wasm export (needs export templates installed):</div>
                <div className="text-amber-400">cd game &amp;&amp; godot --headless --export-release "Web" ../builds/web-shell/game.html</div>
              </div>

              <button
                type="button"
                onClick={handleReload}
                className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-xs transition-colors"
              >
                Check Again
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Footer Info Strip */}
      <footer className="bg-slate-900 border-t border-slate-800 px-4 py-1.5 text-[11px] text-slate-400 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span>Engine: Godot 4.7.2 HTML5</span>
          <span>•</span>
          <span>WASM Mode: Web Workers &amp; SharedArrayBuffer</span>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-slate-500">Pipeline: labs/prd-3d-pipeline.md</span>
        </div>
      </footer>
    </div>
  );
};
