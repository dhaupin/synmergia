# PRD: The Blacksmith -- RYL2-blooded upgrade law
(S16.7, 2026-10-08. Owner directive. Based on RYL2's upgrade process
-- the owner was there; we borrow the bones, lose the wackiness.)

## 0. The fantasy

You grind junk into a weapon worth having, then you GAMBLE it. The
blacksmith is where the world's patience meets the world's cruelty.
Someone walks by with a weapon three tiers brighter than anything
that drops -- and everyone knows what it cost: a pile of sacrificed
brothers, a graveyard of failed forges. "WTF HOW" is the intended
social output. The grind is the fence; the risk is the wall; the
ledger is the proof.

## 1. What RYL2 did (research notes; labs source: RYL2 Devolution
   upgrade guide -- and yes, the guide credits dhaupin)

- 10 upgrade levels at the blacksmith NPC.
- Each +1 attempt costs 10 metals (Silvin / Mithril / Iternium).
- Regular metals CAN FAIL: failure drops the item -1 level or to +0.
- Tobs (Ancient Metals) and Ants (Antoniums) never fail -- but Tobs
  are limited to 3 consecutive uses before regular metals again.
- Gems (5 sockets, S/M/L sizes) add flat stats; effective stat
  multiplies x5 at +10.
- Grades F/D/C/B/A/AA/AAA derive from the item's highest stats.
- The RESET loop: drop the item back to +0, gems' stats are KEPT,
  re-upgrade, repeat -- hundreds of times. On private servers this
  loop went wacky (stats to 4000+). That wackiness is the lesson:
  unbounded loops need unbounded-respectful caps.

## 2. Synmergia's variant (the laws)

### 2.1 Ore grades (5, parity with the weapon scale)

Ores are Item .tres in data/resources/ (res_ prefix), graded on the
same scale as weapons. The Item.Rarity enum already carries 6 tiers
(COMMON..MYTHIC); ores use 5 of them:

    res_ore_copper    COMMON      low chance, common drops
    res_ore_silver    RARE
    res_ore_golden    EPIC
    res_ore_starmetal LEGENDARY
    res_ore_mythril   MYTHIC      ~90% success, vanishingly rare

The existing res_iron_ore stays as the COMMON starter ore (it is
already registered, stackable, purse-lawful). Grades assimilate to
weapon/armor upgrade tier: an ore's grade IS the tier of item it can
meaningfully attempt.

### 2.2 The upgrade gate (who may attempt what)

- The TARGET item must be same tier or LOWER than the sacrificial
  item's tier; the sacrifice is a real equipped/equippable item of
  the SAME tier, with a HIGHER stat than the target's current stat.
- Ores must be the target's tier or higher. Lower-tier ores are
  allowed but lower the success chance; higher-tier ores raise it.
- Failure DESTROYS THE SACRIFICE (the failed forge). The target
  survives. The ore is always consumed.

### 2.3 Success chance

    base(tier)    rises with target tier (a +0 junk swing is easier
                  than a +7 epic)
    ore_bonus     ore grade vs target tier: -15% below, 0% equal,
                  +10% per grade above, mythic-cap ~90% total
    soft_cap_hit  beyond soft cap each further attempt halves the
                  ore bonus (economically irrational to continue)

The exact per-tier tables are balance data (a BalanceData .tres), not
code constants. The service reads the table; the table is tunable
without a recompile.

### 2.4 Soft cap and hard cap

- HARD CAP: the game-limited maximum for that item's stat class
  (damage, defense, magic, heal). Beyond it the upgrade REFUSES --
  not a chance penalty, a wall. This is what keeps the world's
  numbers from skewing.
- SOFT CAP: the economic fence. Past it, success shrinks per the
  half-life rule above. Nothing stops you; arithmetic does.
- Every item carries five balance levels: base, low, mid, soft, hard
  (BalanceData), consumed by scaling and balance, not just the
  blacksmith.

### 2.5 The wackiness guard (the RYL2 lesson)

RYL2's reset-keeps-gems loop compounded unboundedly on private
servers. Synmergia's guard is structural:
- upgrades carry item_level forward, hard cap is ABSOLUTE,
- no reset loop that preserves gains (a reset is a real reset),
- every upgrade is a world delta with provenance (actor, epoch,
  sacrifice id, ores, result) -- the ledger can answer "how did this
  weapon get here," and a duplicated stat trail is detectable.

## 3. Data + code shape

- data/resources/: 5 ore .tres (Item schema, RESOURCE category,
  rarity field = grade, stackable).
- BalanceData schema (labs/prd-scaling.md tenant): base/low/mid/
  soft/hard per stat class per tier.
- BlacksmithService (future): attempt_upgrade(player, target,
  sacrifice, ores[]) -> {ok, reason | upgraded, new_stat}; rides
  InventoryService purses, SecurityService duplication checks, and
  writes world deltas (the AncientDoor/HarvestService law) with the
  full bill of materials as provenance.
- The blacksmith NPC: an interaction node (E), not a UI invented
  from nothing -- the interaction layer's contract.

## 4. Build order

1. Ore .tres ladder (5 grades) + BalanceData schema.
2. BlacksmithService: gate law + chance table + sacrifice
   destruction, headless probe first.
3. The interaction node + panel (a11y-labeled, the MountUI shape).
4. Economy wiring: ore drops into HarvestService nodes and loot
   tables; the grind loop closes.

## 5. Explicitly out of scope

- Gem sockets (RYL2's gem law) -- later PRD; do not let the socket
  shape leak into the upgrade service.
- Trading upgraded items across accounts without provenance (the
  delta ledger must survive transfer).
- Any success table that cannot be expressed as data.

## 6. Research addendum (RYL Return official system page, read 2026-10-08)

Mechanics this PRD missed on first pass, now adopted:
- FAILED FORGE COSTS ENDURANCE: a failure can downgrade one level
  AND strip 1-10 max endurance. Durability becomes a resource the
  gamble eats -- a sword that survives five failures is SCARRED, and
  scars are character. Add: items carry max_endurance; failures roll
  1-10 damage; endurance repair is a crafting/cost surface.
- STAT TRANSFER LAW (the "fuser" mechanic, formalized): a
  sacrificial item transfers a stat ONLY if strictly superior
  (inferior and equal are refused -- red/white vs green). Cost
  auto-scales from target grade + upgrade level + chosen stat. The
  sacrifice is consumed whether the transfer succeeds or not.
  Constraint preserved: min damage can never exceed max damage.
- RINGS AND NECKLACES: never upgradable, never stat-transferable
  (accessories are a different law; note for the service's item
  filter).
- COST FORMULA: upgrade cost auto-calculated from item quality,
  grade, stats, and current upgrade level -- not a flat table. The
  BalanceData tenant should expose the cost curve, not constants.
