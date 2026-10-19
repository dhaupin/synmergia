# Synmergia — Web & Site Deployment Guide

> Scope: the browser surface only — the **site** (`src/`, Cloudflare
> Pages) and the **raw game client** (`web/` → served at `/game/`).
> For the Docker game server (Godot headless + bridges + Postgres),
> see the main [DEPLOY.md](./DEPLOY.md) — this guide complements it.
> **Last updated:** 2026-10-19

---

## 1. Architecture in one screen

```
synmergia.creadev.org            (Cloudflare Pages, static)
├── /            site lander  (prerendered HTML + React hydrate)
├── /play        play page    → frames the WASM client  [GATED]
├── /privacy     legal        (prerendered)
├── /terms       legal        (prerendered)
├── /admin       ops dash     → live bridge tooling     [GATED]
├── /game/       RAW ENGINE CLIENT (shell + wasm + pck)
│     ├── index.html, game.js, game.wasm   (the engine shell)
│     ├── game.pck + game.pck.hash         (packed content)
│     └── *_worklet.js + workers           (audio/threads)
└── itch.io / other ports: upload the CONTENTS of dist/game/
```

Layout law:
- `web/` is the **source folder** of the engine shell (CI re-packs
  `game.pck` here on every push to main and commits it back with a
  new hash + in-game build stamp).
- The **serving URL** is `/game/` (single-domain law: no second
  subdomain, no cross-origin COOP/COEP friction). The legacy `/web/`
  URL still resolves on dev/preview for old bookmarks — never link
  to it from new code.
- `src/` is the site (Vite + React + Tailwind v4 tokens, prerendered
  by prestruct at build time: `npm run build` = `vite build` +
  `scripts/prerender.js`, see `ssr.config.js` for the route list).

Stack: Vite 7 · React 19 · react-router-dom 6 · Tailwind v4
(Bolete-style token architecture, dark Nocturne first) · prestruct
prerender · Cloudflare Pages.

---

## 2. Cloudflare Pages setup (the web path you'll actually use)

1. **Connect the repo** — Pages → Create project → Git →
   `dhaupin/synmergia`, production branch `main`.
2. **Build settings**:
   - Build command: `npm run build`
   - Output directory: `dist`
3. **Node version**: set `NODE_VERSION` = `20` (Pages default is
   fine, but pin it — the bracket toolchain assumes 20+).
4. **Environment variables** (Settings → Environment):
   Both are optional at build time but degrade the product when
   unset (see §3). They are **public-derived hashes**, not secrets
   in the traditional sense — a static bundle cannot hide them.
5. **Deploy**. First deploy must be triggered from the dashboard
   ("Create deployment"); later pushes to `main` auto-deploy.

Why this is safe to build on a free CI: the heavy artifact (the
46 MB wasm bundle) is committed in-repo (`web/`), so a Pages build
just copies files — no Godot, no Emscripten. The GitHub Actions
workflow (`web-ci.yml`) only re-packs content builds; wasm rebuilds
are deliberate events.

### Custom domain

Dashboard → Custom domains → `synmergia.creadev.org`. The
`_headers` file (see §4) deploys with the bundle, so isolation
headers arrive with the domain automatically.

---

## 3. Access gates (`/play` + `/admin`)

Both gated routes share one mechanism (`src/lib/gate.ts` +
`src/components/GateScreen.tsx`): a password field whose sha256 is
compared against a **build-time env var**, success remembered in
`sessionStorage` for the tab session.

| Route | Env var at BUILD time | Unset behavior |
|---|---|---|
| `/play` | `VITE_GAME_PASSWORD_SHA` | gate shows "coming soon", always rejects |
| `/admin` | `VITE_ADMIN_PASSWORD_SHA` | gate shows config error, always rejects |

**Generate the hash** (macOS/Linux):

```bash
printf 'your-password-here' | sha256sum
# → paste ONLY the hex digest into the env var
```

Then set in Pages → Settings → Environment → **Production**:

```
VITE_GAME_PASSWORD_SHA   <hex>
VITE_ADMIN_PASSWORD_SHA  <hex>
```

And trigger a rebuild — these are compile-time constants baked into
the bundle (`import.meta.env`), so a deploy is required after any
change. Never send the plaintext anywhere; only the hash is needed.

### Honest threat model (read before trusting this)

A static site **cannot** keep a gate secret from a determined
read-the-bundle attacker: the sha256 ships in the clear, and offline
brute-force is theoretically possible. Layered reality:

1. This client gate = friction against casual lookers and lazy
   scripts (does its job for a pre-launch teaser).
2. **The real wall is the Cloudflare WAF rate rule** (§5) — it stops
   the brute-forcer that actually tries 10k requests.
3. The bridge/admin data itself is protected server-side: the
   pG/Redis bridges must **bind to loopback** inside the game-server
   container (they do, per the main DEPLOY.md) and are only reachable
   through the Pages proxy where CORS + origin checks apply.

If/when admin needs a real boundary, the upgrade path is Cloudflare
Access (Zero Trust) in front of `/admin*` — no app code change
needed once the route is a real path (it now is, `/admin`).

---

## 4. Isolation + cache headers

`public/_headers` ships the two laws to Cloudflare Files:

```http
/*                                        COOP: same-origin + COEP: require-corp
/game/game.pck                            Cache-Control: public, max-age=86400
/game/game.wasm                           Cache-Control: public, max-age=86400
/game/game.pck.hash                       Cache-Control: no-cache
/index.html + /game/index.html            Cache-Control: no-cache
```

- **COOP/COEP** = Godot 4.7 threads law (SharedArrayBuffer). Without
  these on the host, the engine silently runs single-threaded or
  refuses to boot on some browsers. Nightly verified in
  `web-ci.yml` lint runs.
- **Pack cache law** mirrors the dev/preview handler in
  `vite.config.ts`: the content-addressed pack revalidates via the
  `?v=<hash>` URL (immutable per build) while the anchors
  (`index.html`, `game.pck.hash`) stay fresh — a new CI pack lands on
  the next reload, no hard-refresh needed.

For OTHER hosts, replicate exactly these headers. Any static host
that won't set COOP/COEP cannot serve the threaded client.

---

## 5. Rate limiting / QoS against gate brute-force

Cloudflare (free plan) → Security → WAF → **Rate limiting rules**:

```
Name:      synmergia-gate-bruteforce
Field:     URI Path
Operator:  equals
Value:     /admin            (make a second rule for /play)
Rate:      > 10 requests / 1 minute
Action:    Block for 10 minutes
```

Notes:
- These thresholds assume humans + bots, tuned for a solo operator.
- The static gate does not make server requests per attempt, so the
  *effective* lever is the client retry-cooldown in
  `src/lib/gate.ts` (5 s doubling → 5 min cap, per page load) — the
  WAF rule is the defense-in-depth layer for scripted abuse that
  skips the UI.
- The itch.io port has its own rate machinery (they throttle page
  loads natively); no extra rule needed for that surface.

---

## 6. Pre-launch checklist

- [ ] `VITE_GAME_PASSWORD_SHA` set in Pages prod env
- [ ] `VITE_ADMIN_PASSWORD_SHA` set in Pages prod env
- [ ] WAF rate rules active for `/admin` and `/play`
- [ ] `_headers` deployed (curl -sI the /game/index.html URL and
      check for `cross-origin-opener-policy`)
- [ ] `/game/game.pck.hash` live and equal to the tracked file
- [ ] In-game truth line shows a hash, not `dev`
- [ ] External ports (itch.io) updated from latest `dist/game/`

---

## 7. Local development (web surface)

```bash
bun install
bun run dev        # site at :3000, /game/ served from web/ by the middleware
bun run build      # site + prerender (5 routes) into dist/
bun run preview    # serve dist/ as the host would (headers included)
```

The gates read the same env vars from `.env.local` (File →
New → `VITE_ADMIN_PASSWORD_SHA=<hex>` and
`VITE_GAME_PASSWORD_SHA=<hex>`) — same hashes, so dev behaves like
prod.

### Fresh pack for local testing

```bash
./scripts/pack_web.sh   # zero-waste re-pack of web/game.pck
```

---

## 8. Troubleshooting (web surface)

| Symptom | Cause | Fix |
|---|---|---|
| Blank /game pane | wasm didn't get COOP/COEP | check `curl -I https://…/game/index.html` for both headers |
| Truth line says `dev` | pack built outside CI | run `web-ci.yml` workflow (dispatch) or set the hash manually |
| Gate always rejects | env var missing → hash is '' | set it in Pages env + **redeploy** |
| Pack never updates | hash file cached | confirm `/game/game.pck.hash` returns `no-cache` |
| 404 on `/play` | `dist/play/index.html` missing | prerenderer failed → push again; it fails open as SPA |
