# Synmergia Web Client (engine shell)

This directory holds the **raw game client**: the hand-maintained
engine shell (`index.html`, `game.js`), the engine binary
(`game.wasm`), workers, and the packed content (`game.pck` +
`game.pck.hash`). It is NOT a standalone site — it is the frame that
src/ (the website) loads.

## Serving law: `/game/` on the single domain

The raw client is served at **`/game/`** on the same origin as the
site (single-domain law — one domain, zero cross-origin COOP/COEP
friction for SharedArrayBuffer threads):

- **Dev/preview:** `vite.config.ts` (`serveGodotWeb`) serves this
  directory at `/game/` (and keeps the legacy `/web/` path working as
  an alias for old bookmarks — do not link to it from new code).
- **Production (Cloudflare Pages / Freebuff hosting):** the Vite build
  copies this directory to `dist/game/`; the host serves it as files.
- **External ports (itch.io etc.):** upload the contents of
  `dist/game/` (equivalently this directory) as the game package.

New code must link `/game/index.html`, never `/web/index.html`.

## Pack freshness

`web-ci.yml` re-exports `game.pck` on every push to main and commits
it back with a rewritten `game.pck.hash`. The shell fetches that hash
(no-store) and loads `game.pck?v=<hash>` — one immutable cache entry
per content build. CI also bakes `application/config/build_hash` into
the pack so the in-game truth line can prove which content commit is
running.

## Editing the shell

`index.html` is hand-maintained (progress bar, permission-note
explainer, watchdog, per-file loader labels). A stock Godot export
would clobber it — the CI full-export path deliberately writes to
`builds/web-shell/`, never here. Engine binary (`game.js`/`game.wasm`)
only changes on a deliberate Godot version bump.
