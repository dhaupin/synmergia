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

## 2. Cloudflare Pages setup (verified working 2026-10-19)

First production deploy is live off this exact recipe.

1. **Connect the repo** — Pages → Create project → Git →
   `dhaupin/synmergia`, production branch `main`.
2. **Build settings** (set during project creation — the setup
   wizard has fields for both):
   - Build command: `npm run build`
   - Output directory: `dist`
   - Root directory: `/` (repo root — leave the default; the site is
     a top-level Vite project, not a subdirectory build)
3. **Environment variables** — add these **during setup** in the
   wizard's Environment variables section (or Settings → Environment
   later; both Production and Preview get the same set):

   | Variable | Value | Why |
   |---|---|---|
   | `BUN_VERSION` | `1.4.2` | **Required.** Pages auto-detects bun 1.2.x, which cannot read our `bun.lock` (lockfileVersion 2) and dies on `bun install --frozen-lockfile` with "Unknown lockfile version" — this broke the first deploy on 2026-10-19. Set it in the wizard and the problem never occurs. |
   | `NODE_VERSION` | `20` | Recommended pin. Pages detects Node 22 today, which also works, but pin it so future runtime bumps can't surprise the toolchain. |
   | `VITE_GAME_PASSWORD_SHA` | sha256 hex of your play key — **plain-text var, not secret** | Optional at build time; unset = /play always rejects (fail-closed "coming soon" wall). |
   | `VITE_ADMIN_PASSWORD_SHA` | sha256 hex of your operator pass — **plain-text var, not secret** | Optional at build time; unset = /admin gate shows "not configured" and rejects. |

   Both gate hashes go in as plain-text (text) vars, never "secret":
   they are SHA-256 digests, not passwords, and any `VITE_*` var is
   inlined into the public client bundle by Vite anyway, so the hex is
   public no matter which type you pick. Secret vars in the CF
   dashboard are write-only (you can't view them later without
   overwriting), which you'd regret the first time you need to rotate
   or copy the hash. Source the hash from a ≥ 20-char random
   passphrase: the digest ships in the bundle, so a short password
   could be brute-forced offline against it.

4. **Deploy**. First deploy must be triggered from the dashboard
   ("Create deployment"); later pushes to `main` auto-deploy.
5. **WAF rate rules** (post-deploy, dashboard → Security → WAF):
   add the two gate rate-limit rules from **§5 below** — locking the
   door before anyone finds it is cheaper than reacting.

Why this is safe to build on a free CI: the heavy artifact (the
46 MB wasm bundle) is committed in-repo (`web/`), so a Pages build
just copies files — no Godot, no Emscripten. The GitHub Actions
workflow (`web-ci.yml`) only re-packs content builds; wasm rebuilds
are deliberate events.

### Custom domain

Dashboard → Custom domains → `synmergia.creadev.org`. The
`_headers` file (see §4) deploys with the bundle, so isolation
headers arrive with the domain automatically.

### Oversize assets: game.wasm lives in R2 (required)

Cloudflare Pages caps a Pages site at **25 MiB per file** — no plan
override exists, and Workers static assets cap identically (Pages
limits doc: developers.cloudflare.com/pages/platform/limits). Our
Godot engine binary (`web/game.wasm`, ~38 MB) cannot ship in the
bundle, so the 2026-10-19 deploy died at asset validation:

```
✘ [ERROR] Error: Pages only supports files up to 25 MiB in size
  game/game.wasm is 37 MiB in size
```

The fix is the documented pattern (Pages + R2 tutorial:
developers.cloudflare.com/pages/tutorials/use-r2-as-static-asset-
storage-for-pages): a Pages Function streams the object straight from
R2, same URL, zero client changes. Setup, four steps:

1. **Create the bucket** — Dashboard → R2 → Create bucket → name
   `synmergia-client`, location Auto. No public access needed; the
   binding is private.
2. **Bind it** — synmergia-web Pages project → Settings → Bindings →
   Add binding → R2 bucket → variable name `R2_GAME_WASM`, bucket
   `synmergia-client`. Do it for BOTH Production and Preview
   environments, or the Preview deploys 503 on /game/game.wasm.
3. **Upload the engine once per export** —

   ```bash
   npm run r2:put:wasm
   # = wrangler r2 object put synmergia-client/game.wasm
   #     --file web/game.wasm --content-type application/wasm
   ```

   First run does `npx wrangler login` in a browser; everything after
   is one command, and it only ever runs when you re-export the Godot
   template (the same rare event that changes `web/game.wasm` at all).
   CI never touches R2 — the pipeline only re-packs game.pck, which at
   5.8 MB is far under the cap and stays a build-time asset.
4. **Redeploy** — push to `main` (or trigger from the dashboard).

Verify after deploy:

```bash
curl -sI https://<site>/game/game.wasm | head
# 200, Content-Type: application/wasm, ~38 MB Content-Length
```

Plumbing (all committed):

- `functions/game/game.wasm.js` — the streamer: Range pass-through,
  same cache law as `_headers` (wasm = 1-day TTL; boot anchors keep a
  re-export honest), 404 with the upload command if the object is
  missing, 503 with the fix if the binding isn't wired.
- `vite.config.ts` copy plugin — files over the cap are excluded from
  `dist/game/` (logged + noted in `dist/game/_oversize.txt`), so the
  validation error cannot recur as the project grows. **When
  `game.pck` someday crosses 25 MiB**, copy the pattern: a second
  function at `functions/game/game.pck.js` (key `game.pck` in the
  same bucket) and either rebuild the pck-in-CI pipeline to upload it
  or start pushing packs manually.

Also filed as the known alternative (not chosen): Godot's
size-optimized Web export template could shrink the wasm under 25 MiB
with zero infra — traded against engine performance in a 3D open
world, so R2 won.

### Custom domain

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
