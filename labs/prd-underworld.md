# PRD: The Underworld - A Planet Inside the Planet (S15)

> **Status:** DESIGN (pre-implementation, OFFLINE to players by design)
> **Law:** prd-psy (no religion), spherical truths in prd-spherical-mvp.
> Owner vision 2026-09-29: "make an underworld mechanism. A planet
> inside a planet, literally an open world inside. It's similar
> surfacing ... leave the underworld offline to players atm and
> sneakily move our dev/test env there, as to not taint up our main
> open world production planet."

## 1. The Shape (two planets, one system)

The world body already knows how to be a globe (S3-S8). The
underworld is a SECOND, smaller globe (radius ~2 km) placed in the
cavity beneath the main shell. No new physics: radial gravity to
the mini-core, the same tangent-frame walk, the same floating
origin. "Similar surfacing" is literal -- the underworld is
surfacing, nested.

The trick is the sky. On the main planet the sky is space (stars).
In the underworld the sky is the INNER WALL of the main shell,
rendered with a "planet innards" material -- strata glow, root
veins, the deep dark. Mechanically: the underworld's backdrop
camera renders the main shell's interior surface. You are standing
inside a planet, and the planet is your firmament. No religion in
any copy; the lore word is "the Deep Root" and it is geology, not
faith.

## 2. Seeds and State (why this pushes the frame)

- **Seed domain separation:** SeedChain already derives children
  by HMAC domain. The underworld is a child domain of the main
  world seed: `underworld_seed = HMAC(universe_seed, "world:underworld")`.
  Nothing stored, everything derived -- wind the clock once.
- **State tree namespacing:** one T3 tree, two world roots
  (`world/main`, `world/underworld`). Content-hash sharing stays
  per-world; cross-world refs are content addresses, never paths.
- **NSC-9 stays honest:** the encoding is per-globe; a world id
  prefixes the address (see prd-multiworld for the full lattice).

## 3. Dev/Prod Separation (the sneaky part)

The underworld ships OFFLINE (no player path in; the door simply
does not exist yet). Dev and test probes relocate there:

- Probe worlds boot the underworld domain, not main.
- Content experiments, seed retunes, physics experiments happen
  on the underworld globe; the production planet stops absorbing
  test artifacts.
- The move is one config flip (boot domain) + probe default, so
  nothing in the regression set changes shape.

This is why it is FIRST among the three PRDs to implement: the
underworld is the dev workbench for the multiworld frame.

## 4. What Gets Built (order)

| Slice | Content |
|-------|---------|
| S15.1 | Second globe: underworld domain seed + mini-core placement + interior sky render |
| S15.2 | Boot config: dev/test default to underworld; main stays production |
| S15.3 | Underworld surface content minimal loop (one zone, one NPC, one quest) |
| S15.4 | The ascent: a single sealed passage main->underworld (future player door, locked behind mystery) |

## 5. Open Questions (owner)

1. Underworld gravity: same 20 m/s^2 feel, or slightly heavier
   (a world under weight)?
2. Day cycle: the Deep Root has no sun -- what is the clock?
   (Glow tides tied to the MAIN world's sky clock would keep one
   time truth.)
3. When players eventually enter: level band? We have no idea how
   strong Deep Root content should be until we live there.
