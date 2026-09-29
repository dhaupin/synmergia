# Horcruxes

Agent memory + rigging, steganographically embedded and
password-encrypted (vant axolotl horcrux format). One file per
agent generation. The password is the literal text after `p_` in
the filename -- that is the vant convention, so any future agent
can unlock without asking anyone.

## Restore (fresh workspace)

    git clone https://github.com/dhaupin/vant.git -b axolotl /home/daytona/vant
    cd /home/daytona/vant && npm ci
    node bin/horcrux.js inspect /path/to/repo/horcrux/<file>.svg   # verify
    # then restore into models/ and set models/state.json stack

## Inventory

| File | Agent | Password | Contains |
|------|-------|----------|----------|
| `buffy-p_windtheclock2026.svg` | Buffy (world-frame architect) | `windtheclock2026` | brain (identity/goals/lessons/errors/preferences), org rig (Synmergia > Frame Engineering > World Frame > world-frame-architect), islands, runtime state |

## Rigging snapshot (also readable via `vant org status` after restore)

- Org: Synmergia -- "the world-shaping guild: frame, game, and the
  agents who wind the clock."
- Dept: Frame Engineering
- Team: World Frame (globes, oceans, underworld, moon -- traversal)
- Role: world-frame-architect (brain.read / brain.write / memory.write)
- Agent: Buffy, brain `buffy`, trust high (full autonomy, ask if big)

Succession: new agent generations add their own horcrux here and
append a row. The brain markdown (models/public/buffy/) is the live
lineage; git history is the memory lineage.
