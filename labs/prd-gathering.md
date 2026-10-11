# PRD: Gathering -- the world's giving law
(S16.8, 2026-10-08. Companion to prd-blacksmith.md: ores are the
blacksmith's food; gathering is where they come from.)

## 0. The thesis

The world gives on a schedule the SEED owns, and remembers every gift
in the one ledger. HarvestService (S16.5.3) already carries the
mechanics: nodes register, citizens harvest through the gate chain,
the node depletes, the world grows it back, and every step is a world
delta with provenance. This PRD adds only what the mechanics lack:
WHERE nodes live, WHAT they carry, and WHO the world lets take it.

## 1. Node placement law (seed-derived, clock thesis)

Node positions derive from the zone's seed (SeedChain path
"world:<id>:zone:<zid>:gather"), not from hand placement:

    node_pos(i) = zone_center + ring_offset(seed, i)   -- deterministic

Two registries from the same universe seed place identical nodes.
Hand-placed hero nodes (a named ancient tree) are ALLOWED as
declarations that override the derivation for their index -- the seed
is the default, the designer is the exception.

## 2. Grade distribution (danger is the faucet)

Ore grades (prd-blacksmith.md 2.1) distribute by zone danger, not by
zone level alone:

    zone danger tier (from enemy data: max enemy tier in zone)
      low      -> copper (dominant), rare silver
      mid      -> silver/golden mix
      high     -> golden/starmetal
      mythic   -> starmetal/mythril, contested zones only

The distribution table is BalanceData (tunable), the DERIVATION is
the seed. Griefing pressure is intentional: mythic ore lives where
PvP and elite enemies live. The blacksmith economy's ceiling is set
by where people are willing to die.

## 3. Respawn law (already shipped, declared here)

- respawn_sec per node from BalanceData by grade (common fast,
  mythic slow -- the world hoards its best).
- Respawn timing may derive from the sky clock (SignService) in a
  later pass: nodes ready at DAWN, not on a stopwatch -- the clock
  thesis applied to scarcity. v1 keeps stopwatch respawns.

## 4. The tools (who may gather)

- Bare hands: copper only (slow, QoS-limited).
- Tools (future crafting output, prd-crafting.md): pick grades gate
  ore grades -- a copper pick cannot bite starmetal. The tool check
  rides the same gate chain; no special-casing.
- Species-agnostic: every citizen harvests through HarvestService's
  one chain (already proven by probe -- human and synthetic
  identical).

## 5. The ledger (already shipped, declared here)

Every harvest is a world delta (harvest/<node_id>, actor, epoch);
depletion and respawn are both on the ledger. Anti-abuse rides the
agent law (prd-agent-law.md): harvest cadence beyond the human
envelope is a detector class, not a rate-limit footnote.

## 6. Build order

1. GatherableData .tres (or BalanceData tenant): grade, respawn,
   tool requirement per node class.
2. Seed-derived placement in the globe world builder (zone scan ->
   HarvestService.register_node).
3. Danger-tier distribution table.
4. Tools gate (with prd-crafting.md's tool outputs).
5. Dawn-clock respawn (v2).

## 7. Explicitly out of scope

- Node claiming/territory (dwellings own plots, not the wilds).
- Instanced gathering nodes (bout rooms have no ore).
- Any placement that cannot be re-derived from the seed + zone id.
