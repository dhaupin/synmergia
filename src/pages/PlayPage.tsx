import { useEffect, useRef, useState } from 'react';
import { Maximize2, RotateCw, AlertCircle } from 'lucide-react';

// Play page: the raw web client (web/) is served under /game/ on the
// same origin (single-domain law: one domain, zero cross-origin COOP/
// COEP friction for SharedArrayBuffer threads). Vite dev serves the
// /game path via the static middleware; production hosts copy
// dist/web -> /game at deploy.
const GAME_BASE = '/game/';

export default function PlayPage() {
  const containerRef = useRef<HTMLDivElement>(null);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [missing, setMissing] = useState<null | { title: string; body: string }>(null);

  useEffect(() => {
    fetch(`${GAME_BASE}index.html`, { method: 'HEAD' })
      .then((res) => {
        if (res.ok) return;
        setMissing({
          title: 'Web client not deployed at /game/',
          body: 'The engine shell (dist/web) must be served under /game/ by the host. On Cloudflare Pages this is a copy step in the build; locally the dev server handles it.',
        });
      })
      .catch(() => {
        setMissing({
          title: 'Web client not reachable',
          body: 'Could not reach /game/index.html on this origin. The engine shell (dist/web) is missing from this deployment.',
        });
      });
  }, []);

  const handleReload = () => {
    if (iframeRef.current) {
      iframeRef.current.src = `${GAME_BASE}index.html?t=${Date.now()}`;
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
    <div className="max-w-6xl mx-auto px-4 py-6">
      <div
        ref={containerRef}
        className="relative w-full rounded-xl border border-line bg-black overflow-hidden"
        style={{ aspectRatio: '16 / 10' }}
      >
        <iframe
          ref={iframeRef}
          src={`${GAME_BASE}index.html`}
          title="Synmergia — Godot Web Client"
          className="w-full h-full border-0 absolute inset-0"
          allow="cross-origin-isolated; autoplay; fullscreen; gamepad"
        />

        {/* Control chrome: the two actions that matter */}
        <div className="absolute top-2 right-2 z-30 flex items-center gap-2">
          <button
            type="button"
            onClick={handleReload}
            className="p-2 rounded bg-surface/90 hover:bg-surface text-ink transition-colors"
            title="Restart the engine (fresh pack fetch)"
          >
            <RotateCw className="w-4 h-4" />
          </button>
          <button
            type="button"
            onClick={handleToggleFullscreen}
            className="p-2 rounded bg-accent/90 hover:bg-accent text-paper transition-colors"
            title="Toggle fullscreen"
          >
            {isFullscreen ? null : <Maximize2 className="w-4 h-4" />}
          </button>
        </div>

        {missing && (
          <div className="absolute inset-0 bg-paper/95 backdrop-blur-sm flex flex-col items-center justify-center p-6 text-center z-20">
            <div className="max-w-md">
              <AlertCircle className="w-10 h-10 text-err mx-auto mb-3" />
              <h2 className="font-display text-xl mb-2">{missing.title}</h2>
              <p className="text-sm text-ink-soft leading-relaxed">{missing.body}</p>
              <button
                type="button"
                onClick={handleReload}
                className="mt-5 px-4 py-2 rounded bg-surface border border-line text-sm hover:text-accent"
              >
                Check again
              </button>
            </div>
          </div>
        )}
      </div>

      <p className="mt-3 text-xs text-ink-soft text-center">
        Desktop browsers load the WASM engine (~46 MB, cached after the first visit).
        Mobile Safari/Chromium supported; the game runs threaded terrain workers
        when cross-origin isolation is active on this origin.
      </p>
    </div>
  );
}
