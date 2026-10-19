import React, { useState, useEffect, useRef } from 'react';
import { Maximize2, Minimize2, RotateCw, AlertCircle } from 'lucide-react';

// Godot WASM client pane (wasm-first workflow): an iframe around the
// hand-maintained web/ shell, plus honest missing-asset overlays, and
// the only three controls the game actually needs (Reload / Fullscreen
// / Options drawer). The old diagnostic toolbar (pck/shell/wasm
// status chips, "Shell: ready", footer strip) was removed as noise —
// the browser download line and the in-game truth line are the truth
// surfaces now, and both carry the content hash.
export const GodotClientView: React.FC = () => {
  const containerRef = useRef<HTMLDivElement>(null);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [showConfig, setShowConfig] = useState(false);
  const [pckStatus, setPckStatus] = useState<'checking' | 'present' | 'missing'>('checking');
  const [shellStatus, setShellStatus] = useState<'checking' | 'present' | 'missing'>('checking');
  const [wasmStatus, setWasmStatus] = useState<'checking' | 'present' | 'missing'>('checking');

  useEffect(() => {
    fetch('/web/index.html', { method: 'HEAD' })
      .then((res) => setShellStatus(res.ok ? 'present' : 'missing'))
      .catch(() => setShellStatus('missing'));
    fetch('/web/game.pck?v=' + Date.now(), { method: 'HEAD', cache: 'no-store' })
      .then((res) => setPckStatus(res.ok ? 'present' : 'missing'))
      .catch(() => setPckStatus('missing'));
    fetch('/web/game.wasm', { method: 'HEAD', cache: 'no-store' })
      .then((res) => setWasmStatus(res.ok ? 'present' : 'missing'))
      .catch(() => setWasmStatus('missing'));
  }, []);

  // Keyboard focus: the iframe does not receive key events until
  // clicked. Focus it on mount so WASD/input works immediately.
  useEffect(() => {
    if (iframeRef.current) {
      iframeRef.current.focus();
    }
  }, [shellStatus]);

  // Manual reload only: re-pointing the iframe src with a cache-buster
  // is the ONE supported way to force a fresh engine download. We do
  // NOT auto-reload on tab visibility (that re-downloads the whole
  // engine on a phone returning from the lock screen — the exact
  // annoyance this view used to have; Chromium discards the iframe
  // document on memory pressure and the browser itself restores it).
  const handleReload = () => {
    if (iframeRef.current) {
      iframeRef.current.src = `/web/index.html?t=${Date.now()}`;
    }
  };

  useEffect(() => {
    const onFocus = () => {
      if (document.activeElement?.tagName !== 'IFRAME' && iframeRef.current) {
        iframeRef.current.focus();
      }
    };
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, []);

  const handleToggleFullscreen = () => {
    if (!containerRef.current) return;
    if (!document.fullscreenElement) {
      containerRef.current.requestFullscreen().then(() => setIsFullscreen(true)).catch(() => {});
    } else {
      document.exitFullscreen().then(() => setIsFullscreen(false)).catch(() => {});
    }
  };

  return (
    <div ref={containerRef} className="flex-1 flex flex-col bg-black overflow-hidden relative">
      {/* Minimal control bar (Fullscreen is the primary phone action) */}
      <div className="absolute top-2 right-2 z-30 flex items-center gap-2">
        <button
          type="button"
          onClick={() => setShowConfig(!showConfig)}
          className="p-2 rounded bg-slate-900/80 hover:bg-slate-800 text-slate-300 transition-colors"
          title="Engine options"
        >
          <RotateCw className="w-3.5 h-3.5 rotate-45" />
        </button>
        <button
          type="button"
          onClick={handleReload}
          className="p-2 rounded bg-slate-900/80 hover:bg-slate-800 text-slate-300 transition-colors"
          title="Restart the engine (fresh engine download)"
        >
          <RotateCw className="w-4 h-4" />
        </button>
        <button
          type="button"
          onClick={handleToggleFullscreen}
          className="p-2 rounded bg-amber-600/90 hover:bg-amber-600 text-slate-950 transition-colors"
          title="Toggle fullscreen"
        >
          {isFullscreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
        </button>
      </div>

      {/* Options drawer */}
      {showConfig && (
        <div className="absolute top-12 right-2 z-30 w-72 bg-slate-900/95 border border-slate-800 rounded-lg p-3 text-[11px] text-slate-300 shadow-xl">
          <p className="text-slate-400 mb-1.5 font-medium">Engine options</p>
          <p className="text-slate-500 leading-relaxed">
            The WASM heap is baked at export time (memory floor) and grows at runtime.
            Reload pulls a fresh engine + pack the content hash in the loading bar confirms.
          </p>
          <p className="text-slate-500 mt-1.5 leading-relaxed">
            Threads require a cross-origin-isolated context (COOP/COEP) — that is
            always active on this deployment.
          </p>
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

        {/* Notice overlay if the WASM client cannot run */}
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
                Resource Pack (game.pck) Missing
              </h3>
              <p className="text-xs text-slate-300 leading-relaxed mb-4">
                The Godot WASM runtime is ready and cross-origin-isolated, but the
                packed game content (<code className="bg-slate-800 px-1 py-0.5 rounded text-amber-300">web/game.pck</code>) is not
                being served.
              </p>
              <div className="bg-slate-950 rounded-lg p-3 text-left font-mono text-xs text-slate-300 border border-slate-800 mb-4 overflow-x-auto">
                <div className="text-slate-500 mb-1"># Zero-waste local packaging:</div>
                <div className="text-amber-400">./scripts/pack_web.sh</div>
                <div className="text-slate-500 mt-1"># Or via Godot CLI:</div>
                <div className="text-slate-400">cd game &amp;&amp; godot --headless --export-pack "Web" ../web/game.pck</div>
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
    </div>
  );
};
