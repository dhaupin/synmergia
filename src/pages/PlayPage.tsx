import { useEffect, useRef, useState } from 'react';
import { Maximize2, RotateCw, AlertCircle } from 'lucide-react';
import GateScreen from '../components/GateScreen';

// Game lock (pre-launch law): the raw client at /game/ is not public
// yet — /play frames it only for key-holders until launch. Sharing a
// link before launch does nothing; the gate sits in front. The same
// machinery backs /admin, and the Cloudflare WAF rate rule in DEPLOY.md
// is the durable wall behind this friction.

// Play frame: the raw web client (web/) is served under /game/ on the
// same origin (single-domain law: one domain, zero cross-origin COOP/
// COEP friction for SharedArrayBuffer threads). Vite dev serves the
// /game path via the static middleware; production hosts copy
// dist/web -> /game at deploy.
const GAME_BASE = '/game/';
const GAME_HASH =
  (import.meta.env.VITE_GAME_PASSWORD_SHA as string | undefined)?.toLowerCase() || '';

function GameFrame() {
  const containerRef = useRef<HTMLDivElement>(null);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [fsError, setFsError] = useState('');
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

  useEffect(() => {
    // Truth from the browser, not optimistic state — a fullscreen
    // attempt that gets denied must not flip the button into exit mode
    // (the stuck-page state where the expand icon vanishes but the
    // browser never entered fullscreen).
    const onChange = () => {
      setIsFullscreen(Boolean(document.fullscreenElement));
    };
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);

  const handleReload = () => {
    if (iframeRef.current) {
      iframeRef.current.src = `${GAME_BASE}index.html?t=${Date.now()}`;
    }
  };

  const handleToggleFullscreen = () => {
    const el = containerRef.current;
    if (!el) return;
    if (!document.fullscreenElement) {
      // Vendor prefixes: Safari still ships webkitRequestFullscreen and
      // does not recognize the unprefixed call on some versions —
      // without them the button silently does nothing on iOS/mobile
      // Safari (the reported dead button). WebKit also honors the
      // legacy allowFullScreen attribute, set on the iframe below.
      const request =
        el.requestFullscreen ||
        (el as HTMLDivElement & { webkitRequestFullscreen?: () => Promise<void> })
          .webkitRequestFullscreen;
      if (!request) {
        setFsError('Fullscreen is not available in this browser.');
        return;
      }
      request.call(el).then(
        () => setFsError(''),
        (err) => {
          // Surface WHY instead of the silent dead click.
          const reason =
            err?.name === 'NotAllowedError'
              ? 'The browser blocked fullscreen (tap once more or allow it in site settings).'
              : `Fullscreen failed: ${err?.name || 'unknown error'}`;
          setFsError(reason);
        },
      );
    } else {
      document.exitFullscreen().catch(() => {});
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
          allowFullScreen
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
        {fsError && (
          <div className="absolute top-12 right-2 z-30 max-w-[16rem] rounded bg-surface/95 border border-line px-3 py-1.5 text-xs text-ink-soft">
            {fsError}
          </div>
        )}

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

export default function PlayPage() {
  return (
    <GateScreen
      sessionKey="syn_play_ok"
      gateHash={GAME_HASH}
      envVarName="VITE_GAME_PASSWORD_SHA"
      headline="Synmergia is almost ready"
      blurb="The world is booting up — early players only. Got a key? Let yourself in:"
    >
      <GameFrame />
    </GateScreen>
  );
}
