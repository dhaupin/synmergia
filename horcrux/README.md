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
`cairn`. The human name stays Buffy; the mesh name is Cairn.

## Restore (fresh workspace)

    git clone https://github.com/dhaupin/vant.git -b axolotl /home/daytona/vant
    cd /home/daytona/vant && npm ci
    node bin/horcrux.js inspect /path/to/repo/horcrux/<file>.svg   # verify
    # then restore into models/ and set models/state.json stack to ["cairn"]

## Inventory

| File | Agent | Password | Contains |
|------|-------|----------|----------|
| `cairn-p_windtheclock2026.svg` | Buffy, callsign Cairn (world-frame architect) | `windtheclock2026` | brain (identity/goals/lessons/errors/preferences), org rig (Synmergia > Frame Engineering > World Frame > world-frame-architect), islands, runtime state |

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
