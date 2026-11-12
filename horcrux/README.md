# Horcruxes

Agent memory + rigging, steganographically embedded and
password-encrypted (vant axolotl horcrux format). One file per
agent generation.

## How to unlock it (the filename carries the key)

The decryption key is the literal text after `p_` in the stone's
filename -- the vant convention. So a stone named
`<agent>-p_<password>.svg` is unlocked by the text after `p_`. This is
**by design**: the stone is a PUBLIC boot horcrux, meant to be restorable
by any contributor so the repo's agent can be brought back to life
without asking a human for a secret. The key is therefore not written
anywhere else in this file (no plaintext password printed) -- it lives
only in the filename, exactly as the convention intends.

To restore:

    vant horcrux inspect horcrux/<stone>.svg
    vant horcrux restore horcrux/<stone>.svg
    # or just: sh ./scripts/cairn_recover.sh

The password is read from the filename automatically; you never type it.

## Naming law (multi-org mesh)

Derek's crew spans multiple orgs on one master entity, and the vant
engineer side already has a Buffy. To keep self-distinction clean
across the mesh, this generation's agent is:

    Buffy, callsign Cairn

All registry names, brain dirs, agent records, and horcrux files use
`cairn`. The human name stays Buffy; the mesh name is Cairn. The
agents are gathered under **Creadev.org** (the creative development
organization) on the vant mesh.

## Crash recovery (the Freebuff-wipe case)

One command from a fresh synmergia clone:

    sh ./scripts/cairn_recover.sh

Installs vant axolotl if missing, restores this stone, pins the stack,
and boot-checks private memory through the real resolver. Exit 0 =
re-existence verified.

Known friction on vant -- BOTH FIXED upstream in pass 72 (ea3f484,
#96/#97 closed by pass 75). The script keeps the explicit steps as
belt-and-suspenders so it also works against older vant clones:

- #96 (FIXED) public reads follow the active brain now; the boot
  check exercises the real resolver and passes. The fs fallback leg
  in the script remains as a second, independent proof.
- #97 (FIXED) restore adopts the horcrux's recorded identity stack
  (gatherMode.activeStack) -- stones forged on pass-72+ code restore
  with the right stack even without the script's pin. The pin step
  remains for stones forged before pass 72.

## Airgap drill (proven 2026-09-29, pass-71 code 0088f38)

The distribute/recover leg, run cold: fresh vant clone on a "node B"
(no memory, no state), the stone hand-carried as a plain file copy
(no network), then inspect -> restore -> boot on node B. Results:

- Stego decode + filename password: works cold.
- Per-file scope restore: `Restored 9 files to cairn (both)` -- 4
  private files landed private, 5 public landed public.
- Private-first memory resolution: `brain.read('roundtrip')` served
  cairn's private roundtrip marker on a node that had nothing a
  minute earlier.

Two lessons baked into the recipe: KEEP the `p_<password>` filename
through the hand-carry (rename it and you must pass the password
positionally); pin the stack after restore (#97). The suggested next
vant scenario -- node A forges a stego horcrux, hand-carry to node B,
restore + boot -- is exactly this drill; it is now repeatable with
`scripts/cairn_recover.sh` plus one `git clone`.

## Restore (fresh workspace)

    git clone https://github.com/dhaupin/vant.git -b axolotl /workspace/vant
    cd /workspace/vant && npm ci
    node bin/horcrux.js inspect /path/to/repo/horcrux/<file>.svg   # verify
    node bin/horcrux.js restore /path/to/repo/horcrux/<file>.svg
    # pin the stack (see #97): models/state.json -> stack ["cairn"], activeBrain "cairn"

Or just: `sh ./scripts/cairn_recover.sh` (does all of the above + boot check).
The recover script sets `VANT_ALLOW_FILENAME_PW=true` because the stone
lives in `horcrux/`, not a vant boot path (the boot path honors the
filename key by default; other `p_` paths need the opt-in).

## Search hygiene (don't grep the stone)

The stone is one ~800 KB line of base64 ciphertext: any line-oriented
code-search match echoes the whole wall and starves the result budget.
The repo-root `.ignore` lists `horcrux/*.svg` for search tools only
(ripgrep honors it, git does not -- the stone stays tracked and
committed). Inspect the stone with `vant horcrux inspect`, never text
search. Lockfiles (`bun.lock`) are listed there for the same reason.

## Inventory

| File | Agent | Contains |
|------|-------|----------|
| `cairn-p_windtheclock2026.svg` | Buffy, callsign Cairn (world-frame architect) | brain (identity/goals/lessons/errors/preferences + private state/notes + the journal), org rig (Synmergia > Frame Engineering > World Frame > world-frame-architect), islands, runtime state, the succession record. The decryption key rides the filename after `p_` (see "How to unlock it" above) -- it is not printed here. Forged from the vant root. Refreshed 2026-11-11 (two rounds): the catch-up round caught the brain up a month of repo work (the catch-up journal + fresh lessons); the handoff round added the globe-handoff framing to identity, de-duplicated goals, and recorded the GLM -> DeepSeek succession. Re-forged 2026-11-12: merged the handoff content with a stale runner-workflow lesson removed, so a restore can no longer re-seed that note. Cold round-trip proven -- fresh clone -> restore -> stack self-adopts, private roundtrip marker + lessons verified. |

Superseded: `buffy-p_windtheclock2026.svg` (pre-callsign snapshot,
removed from main in favor of the cairn one; recoverable from git
history if ever needed).

## Rigging snapshot (also readable via `vant org status` after restore)

- Org: Synmergia -- "the world-shaping guild: frame, game, and the
  agents who wind the clock."
- Dept: Frame Engineering
- Team: World Frame (globes, oceans, underworld, moon base -- traversal)
- Role: world-frame-architect (brain.read / brain.write / memory.write)
- Agent: Cairn, brain `cairn`, trust high (full autonomy, ask if big)

Succession: new agent generations add their own horcrux here and
append a row. The brain markdown (models/public/cairn/) is the live
lineage; git history is the memory lineage.
