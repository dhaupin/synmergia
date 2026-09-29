# Horcruxes

Agent memory + rigging, steganographically embedded and
password-encrypted (vant axolotl horcrux format). One file per
agent generation. The password is the literal text after `p_` in
the filename -- that is the vant convention, so any future agent
can unlock without asking anyone.

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

Known open friction on vant (filed as issues, both worked around in
the script, not hacks -- just explicit steps):

- #96 `getPublicPath()` is not stack-aware: after a restore into an
  install that has `models/public/vant`, `brain.read(type:'public')`
  cannot see the restored agent's public memory. The script reads
  public memory from disk until this lands.
- #97 horcrux restore union-merges the host's stale stack instead of
  adopting the horcrux's recorded stack; `activeBrain` is left unset.
  The script pins `stack: ["cairn"]` after restore.

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

    git clone https://github.com/dhaupin/vant.git -b axolotl /home/daytona/vant
    cd /home/daytona/vant && npm ci
    node bin/horcrux.js inspect /path/to/repo/horcrux/<file>.svg   # verify
    node bin/horcrux.js restore /path/to/repo/horcrux/<file>.svg
    # pin the stack (see #97): models/state.json -> stack ["cairn"], activeBrain "cairn"

Or just: `sh ./scripts/cairn_recover.sh` (does all of the above + boot check).

## Inventory

| File | Agent | Password | Contains |
|------|-------|----------|----------|
| `cairn-p_windtheclock2026.svg` | Buffy, callsign Cairn (world-frame architect) | `windtheclock2026` | brain (identity/goals/lessons/errors/preferences + private state/notes), org rig (Synmergia > Frame Engineering > World Frame > world-frame-architect), islands, runtime state; forged with pass-71 code (per-file scope tags, type 'both') |

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
