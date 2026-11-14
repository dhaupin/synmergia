import { useEffect } from 'react';
import { mountIslands } from 'prestruct/islands';
import GateScreen from '../components/GateScreen';
import { islands } from '../AppIslands';

// Game lock (pre-launch law): the raw client at /game/ is not public
// yet — /play frames it only for key-holders until launch. Sharing a
// link before launch does nothing; the gate sits in front. The same
// machinery backs /admin, and the Cloudflare WAF rate rule in DEPLOY.md
// is the durable wall behind this friction.
const GAME_HASH =
  (import.meta.env.VITE_GAME_PASSWORD_SHA as string | undefined)?.toLowerCase() || '';

// The game itself is a prestruct island: it is client-only, mounts after the
// gate unlocks, and never runs during the SSR prerender. The island registry
// lives in AppIslands.tsx; this effect is the second mount point (the global
// route-change scan in App.tsx is the first) for the element that appears only
// after a successful unlock.
function PlayGameMount() {
  useEffect(() => {
    const t = setTimeout(() => mountIslands(islands), 0);
    return () => clearTimeout(t);
  }, []);

  return (
    <pre-island data-pre-island="play-game" data-pre-load="eager">
      <div className="max-w-6xl mx-auto px-4 py-6">
        <div
          className="w-full rounded-xl border border-line bg-black/60 grid place-items-center"
          style={{ aspectRatio: '16 / 10' }}
        >
          <p className="text-sm text-ink-soft">Loading the world…</p>
        </div>
      </div>
    </pre-island>
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
      <PlayGameMount />
    </GateScreen>
  );
}
