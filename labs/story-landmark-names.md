# Landmark naming pass — names keyed to the real world coordinates

> **Scope:** `labs/` only. `game/` is read-only context; every coordinate and id
> below is quoted from the terrain law or the data. The point of this pass is to
> give each landmark a name that *matches the thing the code actually places*, so
> a later copy pass never invents a place the world does not have.

---

## Why this pass exists

The world is generated from a handful of authored anchors in
`game/scenes/worlds/terrain_gen.gd` (plus the Sundered backend). Player-facing
copy had drifted into naming *moods* ("the Darkwood", "the far coast") instead of
naming the *anchors the code stands*. This pass keys every name to a real
constant, so the map, the lore, and the walk law agree.

Lat/lon below are computed from the constant directions with the repo's own
spherical law (`lat = asin(y)`, `lon = atan2(z, x)`), on a 20 km-radius planet.

---

## The landmark table

| landmark | code anchor | dir → lat/lon | name (canon) | one-line etymology |
|---|---|---|---|---|
| **The Boot** (spawn shore) | `SPAWN_CENTER = (1, 0, 0)` | 0.0°, 0.0° | **Haven Shore** | the flattened build/walk plaza the village sits on — the boot's own ground |
| **Haven** (village) | village on the boot's hillside (`VILLAGE_HILLSIDE_LIFT`) | 0.0°, 0.0° | **Haven** | a village built inside the colossal fallen machine limb — see `labs/story-chronicle.md` |
| **The Capitol strand** | `cove_axis()` (mid-ring of the cove flat) | 2.8°, 0.0° | **Novo Concord** | the authored city strand ~1.03 km out across the cove; the monolith crowns it |
| **The Cove** | `COVE_BEARING_DEG = 90`, half-width 0.15 | south of the boot | **The Boot Cove** | the authored sea notch cut into the homeland's own plain |
| **The Ferry Island** | `ISLAND_CENTER = (0.866, 0, 0.5)` | 0.0°, 30.0° | **Gull Island** | the offshore plateau the ferry owns; the strait moat cuts its crossing |
| **The Strait** | `STRAIT_CENTER = (-0.24, 0.72, 0.56)` | 49.8°, 113.2° | **The Sundered Strait** | the channel the barque run crosses; the sea tables' site anchor |
| **The Mountain Lake** | `LAKE_CENTER = (0.28, 0.26, 0.92)` | 15.1°, 73.1° | **The High Tarn** | the mountain bowl that drains low (`LAKE_DROP`); fed by the ring range |
| **The Ring Range** | `RING_R0..R2 = 0.26..0.74` | 5.2–14.8 km out | **The Home Ring** | the home-anchored mountain band; the 5+ km backdrop on the turn-around vista |
| **The Deep Root** | `world_underworld.tres` | underworld world | **The Deep Root** | the strata-lit underworld the Warden keeps a hearth in |
| **The Moon** | `world_moon.tres`, `moon_provider.gd` | tide-locked | **The Moon** | hangs over one meridian forever; the moon-shield gates the aurora |

**Anchor note.** Every lat/lon in the table is a pure function of a constant in
`terrain_gen.gd` or the Sundered backend, so these names cannot drift from the
geometry without a code change. If a name ever disagrees with a coordinate, the
coordinate wins — the code is the ground truth, the name is the label.

---

## The one real inconsistency: Gloomwood vs Gloamwood

The Bloom lane's woods are named **two ways** in the shipped data, and this is the
pass that resolves it.

**The split, as found:**

- **Display text says "Gloomwood":** `zone_forest_meadow.tres` ("Gloomwood
  Meadow"), `zone_dungeon_forest_depths.tres` ("Gloomwood Depths"),
  `village_elder_greeting.tres` ("the Gloomwood"), `res_timber.tres`
  ("Gloomwood pine"), `enemy_thistle_boar.tres`, `enemy_gloamwood_stalker.tres`
  (description), and the three `spawn_*.tres` display names.
- **Ids say "Gloamwood"/"gloam":** `enemy_gloamwood_stalker.tres`
  (id `gloamwood_stalker`), `quest_gloamwood_ledger.tres` (id + display name "The
  Gloamwood Ledger"), `quest_gloam_harvest.tres`, `loot_gloam_litter.tres`,
  `loot_gloam_spores.tres`, `res_gloam_spore.tres`, `elixir_gloamward.tres`.

**Resolution (owner call, 2026-11-28):** **Gloamwood is canonical.** "Gloam" is
the word the ids already chose, and "gloam" (the half-light before dark) is the
right register for a Bloom-touched woods. The display strings are corrected to
**Gloamwood**; the ids already agree. This reverses the earlier drift-log note
(which had picked "Gloomwood" off the zone `.tres` + art), so `prd-story.md`'s
drift log is updated to record the reversal rather than the old resolution.

**What changes:** display text only — `display_name` / `description` / dialogue
strings. **What does not change:** any id, filename, or reference. Because the
ids already read "gloam", the sweep is a copy fix with zero resolution risk.

---

## Names that must NOT be invented

Per the voice bible's restraint rule, this pass names *anchors*, not *answers*.
Do not add named ruins, named maker sites, or a named Nexus Core on the strength
of a landmark table — the five mysteries stay open (`prd-story.md` sec. 9). A
landmark gets a name only if the code stands something there.
