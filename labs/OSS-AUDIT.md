# Synmergia — Open Source (MIT) Readiness Audit

**Purpose:** a self-audit checklist for taking Synmergia from "MIT LICENSE
sits in the tree" to "a stranger can clone it, build it, contribute to it,
and we are safe doing that." Written 2026-11-04 against the `staging` tree.

**How to use it:** work top to bottom. Each item is what to check, the
repo's status at time of writing, and the action. A mark is a snapshot,
not a promise — re-verify anything marked done after a big merge.

Legend: `[x]` done · `[~]` partial / needs a decision · `[ ]` open · `[!]` blocker

---

## Progress (2026-11-11 — the build-out round)

The owner's decisions landed and the blockers are cleared. What changed
since the audit was written (see `labs/TASKS.md` 2026-11-11 for the full
receipt):

- **Copyright holder of record:** Creadev.org (LICENSE + `package.json`).
- **All-MIT vs code-MIT:** the whole repo (code + generated content) is
  MIT; third-party pieces are carved out in `CREDITS.md`; the name/logo is
  carved out in `TRADEMARK.md`.
- **§1/§3 blockers DONE:** README License section with carve-outs;
  `TRADEMARK.md`; Godot's MIT notice ships at `web/LICENSE.godot.txt`;
  the two fonts' OFL 1.1 texts ship at `public/fonts/OFL-*.txt`;
  `CREDITS.md` enumerates engine / deps / fonts / asset provenance.
- **§6 blockers DONE:** `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
  (Contributor Covenant v2.1), `SECURITY.md`; `.github/` issue + PR
  templates + `CODEOWNERS`.
- **§4 horcrux decision RESOLVED:** `horcrux/` STAYS (it is the repo's
  recovery contract — see `DEVCODE.md`), and the plaintext password is
  GONE: the key rides the stone's filename after `p_` (the vant
  convention), which is the design — a contributor restores the brain
  without asking a human. The README explains the convention, prints no
  key. `scripts/cairn_recover.sh` sets `VANT_ALLOW_FILENAME_PW=true`.
- **§8 partially DONE:** site `/opensource` links the new docs; README
  links the repo + contributing path.
- **Still open (owner decisions / ops, not blockers):** wasm/pck weight
  (§4) — LFS vs release artifacts; `labs/` disclosure posture (§5);
  Dependabot + branch protection + secret scanning (§7); GitHub repo
  description/topics/social preview (§8). These are recorded, not done.

---

## 1. Licensing (the actual grant)

- [x] **Top-level LICENSE exists and is the intended license.** `LICENSE`
      is MIT. Good.
- [~] **The copyright holder is a deliberate, consistent legal name.**
      Changed to `Copyright (c) 2026 Creadev.org` this round. Decide the
      real holder (person vs. org vs. entity) and use the SAME string in
      LICENSE, package.json, README, and the site footer. If Creadev.org is
      not a registered entity, consider `Creadev.org (Derek Haupin)` or
      similar so the grant has a real party behind it.
- [x] **`package.json` declares the license.** Now `"license": "MIT"`.
      (It is still `"private": true`, which is correct — it is not meant
      to be `npm publish`-ed; that flag is about accidental publishing, not
      about the source being open.)
- [x] **`game/` (Godot project) carries no conflicting license header.**
      No per-file headers to reconcile.
- [x] **Decide: is ALL of the repo under MIT, or just the code?** DECIDED: code + generated content MIT; third-party carved in `CREDITS.md`; brand carved in `TRADEMARK.md`. (was: Right
      now MIT covers everything tracked. If you want the *game code* MIT
      but the *art / audio / brand* under a different (or all-rights-
      reserved / CC) license, say so explicitly — see §3.
- [x] **Add a short "License" section to README** that names MIT, links
      LICENSE, and states any asset carve-outs. (README has a License
      section already; make it carry the carve-outs if any.)
- [x] **Trademark / brand is NOT granted by MIT.** DONE: `TRADEMARK.md`. MIT grants copyright
      rights, not trademark. State plainly that the "Synmergia" name and
      logo are not licensed for reuse by the code grant (prevents someone
      shipping a confusing fork as "Synmergia"). One paragraph, usually in
      README or a TRADEMARK note.

## 2. Secrets & sensitive data (the thing that hurts most if missed)

- [x] **No tracked `.env`.** Only `.env.example` is tracked, with empty
      values. Good.
- [x] **`.env` never committed in history.** `git log --all -- .env` is
      empty. Good.
- [x] **No hardcoded secrets in source.** Scanned tracked `.gd/.ts/.tsx/
      .js/.json/.yml/.md` for `api_key|secret|password|token` literals —
      clean.
- [x] **No secrets in git history.** Scanned commits for PEM blocks, AWS
      keys, GitHub tokens, `sk-` keys, certs — clean.
- [x] **No committed credential files.** No `.pem/.key/.p12/.htpasswd/
      id_rsa` tracked.
- [x] **CI secrets come from GitHub Secrets.** Workflows read
      `secrets.CLOUDFLARE_API_TOKEN` / `github.token`; none are echoed.
- [x] **The `/play` and `/admin` password hashes are not committed.** The
      gate compares against `VITE_*_PASSWORD_SHA` build-time env; no
      plaintext or hash is in the tree.
- [ ] **Run a dedicated scanner anyway before flipping public.** (Still open.) Add
      `gitleaks` / `trufflehog` (or GitHub's push-protection + secret
      scanning) as a one-time sweep, not just grep. Grep misses encodings.
      Enable **GitHub secret scanning + push protection** on the repo.
- [ ] **Confirm no personal data (PII) is tracked.** (Still open.) Player data, test
      accounts, real names beyond the maintainer, emails, IPs. (See §5 for
      the specific `horcrux/` and infra-name items.)

## 3. Third-party assets & attribution (the license-compatibility trap)

MIT is only valid for code **you own**. Every borrowed asset needs its own
compatible license or a written grant.

- [x] **Audio is generated in-repo.** `game/audio/*.wav` come from
      `scripts/gen_*_audio.py`. You own them.
- [x] **3D models are generated in-repo.** `game/models/*.glb` come from
      `scripts/gen_*_model.py`. You own them.
- [x] **`gamestruct` (build dep) is MIT.** Pinned to a `dhaupin/gamestruct`
      commit. Compatible.
- [x] **Self-hosted fonts carry their license files.** DONE: `public/fonts/OFL-Cinzel.txt` + `OFL-PlusJakartaSans.txt`. Cinzel and Plus
      Jakarta Sans (both SIL OFL) are self-hosted in `public/fonts/`, but
      no `OFL.txt` is shipped. **Action:** drop each font's `OFL.txt`
      beside it (or a `public/fonts/LICENSES.md`). OFL requires the
      license travel with the font.
- [x] **Godot Engine attribution is missing from the web export.** DONE: `web/LICENSE.godot.txt` ships beside the export. The
      browser build embeds Godot's runtime (`web/game.js`, `game.wasm`)
      with no license/notice shipped alongside. Godot is MIT — you must
      reproduce its copyright + license notice. **Action:** add a
      `web/LICENSE.godot.txt` (Godot's MIT text + the `(c) 2014-present
      Juan Linietsky, Ariel Manzur and contributors` line) and link it
      from the game shell / README. Same for any other vendored runtime.
- [x] **Enumerate every remaining asset and record provenance.** DONE: `CREDITS.md`. Screenshots
      (`art/screenshots/`), icons, `public/branding/*`, any hand-authored
      PNG/SVG/WAV/GLB not produced by a gen script. For each: who made it,
      under what license, and is it yours to MIT. Put the answer in a
      `CREDITS.md` / `THIRD_PARTY_NOTICES.md`.
- [ ] **No "inspired by" IP leakage.** (Still open -- review the references.) README references "Ultima Online",
      "RYL2 / Risk Your Life 2". Descriptive comparisons are fine; make
      sure no borrowed assets, names, or copied data from those games are
      in the tree.
- [x] **Dependency license sweep.** DONE: swept; all deps MIT/ISC/Apache-2.0, recorded in `CREDITS.md`. Run `license-checker` / `licensee
      over `node_modules` and the Godot addons; confirm every dependency is
      permissive (MIT/Apache/BSD/ISC). Flag any GPL/AGPL/SSPL or
      non-commercial dep — those poison an MIT-only release.
- [x] **Decide the asset license explicitly.** DONE: MIT for code + content, carved in `CREDITS.md` / `TRADEMARK.md`. Even if everything is
      currently "yours", state in README/CREDITS whether art+audio ship
      under MIT, CC-BY-4.0, CC0, or "all rights reserved, code is MIT".

## 4. Repository hygiene (what a cloner actually gets)

- [x] **`.gitignore` is thorough.** Ignores `.godot/`, `*.import`, build
      outputs, `node_modules/`, OS junk, `tools/`, scratch art. Good.
- [x] **No `node_modules` or build output tracked.**
- [ ] **Repo weight.** `web/game.wasm` is 38 MB and `web/game.pck` 6.8 MB
      (both intentionally tracked so `/game/` works). `.git` packs to
      ~186 MB. This is a heavy clone. **Decide:** is a 40 MB tracked
      binary acceptable, or should the wasm/pck move to Git LFS or to
      release artifacts / R2-only? A heavy clone is the #1 first-impression
      killer for a "come contribute" repo.
- [ ] **Scan history for large/accidental blobs.** `git count-objects -vH`
      + `git rev-list --objects --all | git cat-file --batch-check` to find
      blobs that were added then deleted. If something huge or sensitive
      lives in history, decide whether to rewrite history (BFG / filter-repo)
      *before* the repo is public — it is far harder after.
- [x] **`horcrux/` decision RESOLVED.** It STAYS (the repo's recovery contract), and the plaintext password is GONE -- the key rides the stone filename after `p_` by design. Original note: It holds an
      agent-memory stone whose **password is printed in plaintext in
      `horcrux/README.md`** (`p_windtheclock2026`). It is harmless as a
      secret (nothing is protected by it that matters), but it reads as a
      password sitting in a public repo and will get flagged by scanners
      and humans alike. **Decision:** move `horcrux/` out of the public
      tree (private repo / local), or keep it but rename the README table
      so no literal password is published.
- [ ] **No machine-specific absolute paths in tracked files.** Scanned
      `*.gd/*.ts/*.json/*.godot` for `/home/<user>/`, `/Users/<user>/` —
      clean. Re-run after any new probe script.
- [ ] **Line endings + encoding.** Repo is fine (ASCII, LF); keep new files
      ASCII (the repo's own no-UTF-8 rule) and consider a `.gitattributes`
      to normalize EOLs for Windows contributors.
- [ ] **Add a `.editorconfig` note / confirm it is present** so external
      contributors match tabs-in-`.gd` / spaces-in-`.ts` conventions.

## 5. Internal / operational information disclosure

Going public publishes **all docs and history**, including operational
detail you may not want strangers reading.

- [ ] **Review `labs/` before publish.** It is a large internal design +
      session-log corpus (`TASKS.md` alone is ~770 KB) that names infra,
      accounts, deploy steps, and people. Decide: publish as-is (radical
      transparency — fits the "built in the open" voice), publish a curated
      subset, or keep `labs/` private. If published, scan for anything you
      would not say in public.
- [ ] **Scrub or accept production identifiers.** Tracked docs name
      `synmergia.creadev.org`, `play.synmergia.com`, R2 bucket bindings,
      Cloudflare Pages project names, and the deploy/rotate procedure
      (`DEPLOY_WEB.md`). These are not secrets, but they hand an attacker a
      map. Decide per item: keep (it is a public site anyway) or redact.
- [ ] **Confirm the deploy secrets' rotate path is documented** and that
      the doc does not contain the values. (It documents sha256-of-password
      + dashboard rotation — good, just re-check.)
- [ ] **People / org names.** `horcrux/README.md` names an org mesh,
      "Derek", agent codenames. Decide what is fine to publish.
- [ ] **Third-party service keys / webhook endpoints** in code or docs
      (Discord webhooks, payment provider secrets). Confirm all are env-
      driven and none are committed.

## 6. Governance & community files (what makes it *contributable*)

A repo can be legally open and still impossible to contribute to. These
files are the difference.

- [x] **README.** Present and substantial.
- [x] **CONTRIBUTING.md.** DONE (root). Add: how to set up (Godot version,
      `npm ci`/`bun install`, the test runner), the PR process, commit
      style, the tab/ASCII rules, where to ask questions, and the DCO/sign-
      off expectation if any. This is the single most important missing
      file for "come build it with us".
- [x] **CODE_OF_CONDUCT.md.** DONE (Contributor Covenant v2.1). Adopt the Contributor Covenant
      (v2.1) or write a short one. Include the enforcement contact. Required
      by most community norms and by GitHub's community profile.
- [x] **SECURITY.md.** DONE (root, GitHub advisories + scope + posture). State how to report a vulnerability
      **privately** (email or GitHub Security Advisories), what is in scope,
      and the response expectation. Critical for a networked game with an
      economy and auth.
- [x] **Issue + PR templates** (`.github/ISSUE_TEMPLATE/` + `PULL_REQUEST_TEMPLATE.md`). DONE.
      `.github/PULL_REQUEST_TEMPLATE.md`). Guide reports toward repro steps
      and keep PRs reviewable.
- [x] **CODEOWNERS** (`.github/CODEOWNERS`). DONE. Route reviews; even one owner
      line helps.
- [ ] **CHANGELOG.md** (optional but recommended). Or state that GitHub
      Releases are the changelog.
- [ ] **GOVERNANCE.md / decision-making** (optional). For a BDFL project, a
      short "how decisions get made" note prevents contributor friction.
- [x] **AUTHORS / CREDITS.** DONE: `CREDITS.md`. Credit contributors.

## 7. Security & operations posture (you are about to be read by everyone)

- [ ] **Threat model in the open.** The site's own Open Source page says it
      plainly: opening the code means exploit-hunters get a head start.
      Make sure the *server* is the authority (it is, per the architecture)
      and that nothing client-side is trusted. This is a design audit, not
      a doc.
- [ ] **Dependency + supply-chain automation.** Enable Dependabot (or
      Renovate), `npm audit` in CI, and GitHub's dependency review. An
      open repo attracts dependency-confusion and typo-squatting attempts.
- [ ] **Branch protection on `main`.** Require PR review + passing CI
      before merge once the repo is public (you currently push direct to
      `staging`/`main` — fine pre-launch, not for a public repo).
- [ ] **Secret scanning + push protection** enabled (repeat of §2, but it
      belongs in the operational checklist too).
- [ ] **Confirm CI does not leak.** Artifacts, logs, and PR builds must not
      expose secrets or internal endpoints to fork PRs.
- [ ] **License/CLA/DCO decision.** For a game you intend to keep
      developing, decide whether contributions need a DCO sign-off
      (`Signed-off-by`) or a CLA, so the project can relicense later if it
      ever must.

## 8. Release metadata & presentation (first impression)

- [ ] **Repo description + topics on GitHub.** One line ("Browser-first
      spherical-world MMORPG — MIT") + topics (`godot`, `mmorpg`,
      `gdscript`, `webassembly`, `open-source`).
- [ ] **Social preview image.** Use the existing OG card
      (`public/og-image.png`).
- [ ] **README top**: a one-line pitch, a screenshot/GIF, a "Play now"
      link, build status badge, license badge, and a "Contributing" link
      near the top.
- [ ] **Confirm the README's marketing tone is honest** (it is
      enthusiastic; make sure every claim is true and nothing promises
      features that do not exist — the project's own honesty law).
- [x] **Link the site from the repo and the repo from the site.** DONE: `/opensource` links the docs; README links repo + contributing. The
      site's Open Source page links GitHub; add the site link + a
      "Contributing" pointer to the README.
- [ ] **`/opensource` page already tells the "why"** — keep it in sync with
      whatever this audit decides (license holder, contribution path).

---

## The short version — blockers before flipping public

If you do nothing else, these four are the ones that matter:

1. **[x] Godot license notice** shipped with the web export (§3) —
   DONE (`web/LICENSE.godot.txt`).
2. **[x] CONTRIBUTING.md + CODE_OF_CONDUCT.md + SECURITY.md** (§6) — DONE
   (root), plus `.github/` templates + CODEOWNERS.
3. **[x] `horcrux/` decision** (§4) — RESOLVED: it stays; the plaintext
   password is gone (key rides the filename).
4. **[x] Asset license sweep + explicit carve-out** (§3) — DONE
   (`CREDITS.md` + `TRADEMARK.md`).

Everything else is polish, but the repo weight (§4), the `labs/` disclosure
decision (§5), and branch protection (§7) are the next tier.

---

## Decisions to make (not tasks — choices only you can make)

Resolved 2026-11-11:
- **Copyright holder of record:** Creadev.org.
- **License scope:** everything MIT (code + generated content); third-party
  in `CREDITS.md`, brand in `TRADEMARK.md`.
- **`horcrux/`:** in the public tree (recovery contract); no plaintext key.
- **Contributions:** DCO-style `Signed-off-by` requested (no CLA).

Still open:
- Is `labs/` public, curated, or private? (The repo currently publishes it.)
- Does the wasm/pck stay tracked, or move to LFS / release artifacts?
- Dependabot + branch protection + secret scanning (§7) — ops posture.
