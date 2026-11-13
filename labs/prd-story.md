# Synmergia — Story & World Lore (PRD)

> **Status:** CANON. The narrative bible. Systems PRDs (prd.md,
> world-building-arch.md) say how the world RUNS; this document says
> WHY it is the way it is, what happened before the player arrived,
> and what the player's presence means. When gameplay copy, quests,
> or dialogue contradict this document, this document wins -- amend
> it deliberately, never silently.
>
> Consolidates: art-direction.md (visual canon), species/class/
> faction/zone .tres descriptions, NPC dialogues, and the Round 1-4
> Gemini concept set (labs/prompts/). 2026-09-25.

---

## 1. The premise (one paragraph)

Synmergia is an **unpowered world**. Ages ago a symbiotic machine
civilization -- the **Convergence** -- hummed across the land: conduit
lines, waypoint stones, city-halls of ceramic and alloy, and the
agent-fauna tending it all. Then came **the Silence**: every machine
went dark at once, for reasons no survivor fully remembers. Nature
did not wait. Roots and moss and mycelium took the halls, and the
world slept for centuries. Now explorers walk the ruins carrying
**tablets** -- hand-woken fragments of Convergence tech -- and the
whole game is one verb: **find the dormant thing, wake it.** There
are no engines and no manufacturing anywhere; everything that moves
was already here, sleeping, and is woken by hand.

**Why this matters for design:** scarcity is total. Every item is
salvage, repair, or growth. Every service is a repurposed machine
organ. Every ride is a woken creature or platform. The old-MMO
comforts (vendors, banks, trainers, hearths) exist -- as the
overgrown institutions of a dead network half-returning to life.

## 2. Timeline (the deep history)

| Age | Name | What happened |
|-----|------|---------------|
| 1 | **The Convergence** | The machine civilization at its height: conduit lines, islet orb-lifts, agent fauna, the Nexus Central halls, the Spire doors. Humans and Akkan lived at its margins as partners and clients. |
| 2 | **The Silence** | Every Convergence machine went dark in a single season. No blast, no war record -- the halls were simply left mid-task (see sec. 9, Mysteries). |
| 3 | **The Long Sleep** | Centuries. Forests ate the cities. Agent fauna went feral or docile. In the deep green dark, the mycelium network that once SERVED the Convergence kept growing -- untended, purposeless -- and slowly became **the Bloom** (sec. 5). |
| 4 | **The Waking** (present) | Tablet-bearers reappear. Villages like Haven stack timber against dormant hulls. The first waypoint stones flicker teal. The player arrives here. |

## 3. The three species (who is here)

Canon anchors: `game/data/species/species_{human,akkan,synthetic}.tres`.

- **Humans** -- adaptable survivors of the eastern plains; diplomats
  and repairers. They build FROM the ruins: Haven is timber stacked
  against a fallen machine limb. Faction: **Human Alliance**
  (starter_plains). Their edge is empathy with dormant tech --
  first to wake things, first to patch them.
- **Akkans** -- the old blood of the dark highlands: heavy-boned,
  ember-eyed, sigil-carving. Their clans remember the Convergence
  as CLIENTS, not servants -- they guarded its gates and still keep
  cairn-marks along its forgotten roads. Faction: **Akkan Horde**
  (dark_highlands). Sigils are their own art: ember-orange, older
  than the tablets.
- **Synthetics** -- the Convergence's own people: humanoid machines
  who woke up during the Long Sleep and chose sides. Nexus Central
  is their home and their question mark: the Collective tends the
  halls and debates what the Convergence was FOR. To wake a machine
  is, to them, to wake a relative.

No species "built" the Convergence alone -- that asymmetry (two
client peoples, one emergent people, zero makers in evidence) is the
engine of the setting's mystery. See sec. 9.

## 4. Powers & institutions

- **The Convergence** (teal/gold): the dormant network itself --
  waypoints, conduits, spire doors, agent fauna, the Agent Core
  star (its emblem, diegetically: on doors, seals, currency).
  Waking it is the game. Gold marks what is ACTIVE; teal marks what
  CAN be.
- **Aether-Conduits** (canon term, sec. 8.3 of the art bible): the
  player-facing terminals of that network -- service kiosks, house
  address stones, ticket posts. A village with a lit Conduit is a
  village plugged back into the world.
- **The factions** (`faction_*.tres`): Human Alliance, Akkan Horde,
  Synthetic Collective, and the unclaimed Neutral paths. Politics
  in one sentence: the Alliance wants to REBUILD the network, the
  Horde wants to be its GUARDIANS again, the Collective wants to
  UNDERSTAND what they are waking -- and everyone needs the
  tablet-bearers.
- **The institutions** (service interiors, art bible sec. 8.4):
  Vaults keep what survives; Academies re-teach what the machines
  knew (skill upgrades, stat resets); Smiths wake the Forge; the
  Storekeeper trades what cannot be grown. Each is a dormant
  machine repurposed -- the old world's organs, re-staffed.

## 5. The Bloom (antagonist force)

Canon anchors: violet = mycelium/arcane ONLY; magenta = hostility
key (art bible sec. 3, 8.1, 8.2); the Forest Devourer; Feral
Spore-Spider, Shrike-Owl, Rust-Root-Crab, Blight-Lizard; Gloamwood's
violet runoff.

**The Bloom** is the mycelium network gone masterless. It was the
Convergence's garden-tender -- spore-dispersal, soil repair, decay
management. After the Silence it kept growing with no one to tend,
and it has begun to WAKE things wrongly: not with a tablet's polite
teal handshake, but by force. Bloom-touched machines and fauna run
hot violet; their eyes burn magenta -- the wrong color, the
handshake refused (this is why the hostility key is magenta: it is
literally the Bloom's signature on something it took).

What the Bloom wants is the setting's active question. It builds
nothing and destroys little -- it INCORPORATES. The Forest Devourer
is not an attack; it is a thesis: roots grew through the hull and
made the machine part of the garden. The Bloom is at its strongest
where the Convergence sleeps deepest (Gloamwood, the Forest Depths).

**Rule for writers:** the Bloom is tragic, not evil. It is a
caretaker that outlived the thing it cared for. Corrupted agents are
not villains; they are patients. (The frayed cables and cracked
shells in the bestiary are symptoms.)

**The Bloom-touched bestiary** (Act II, `data/enemies/`). The
corruption medium is always the same: the neutral agent fauna, gone
over -- cracked shell, leaking spore-dust or frayed cables, magenta
thread-eyes where teal used to glow (art bible sec. 8.1). Four are
canon from the hostile-agent renders; each is the neutral creature's
taken form:

| Neutral | Bloom-touched | Data id | Notes |
|---------|---------------|---------|-------|
| Spore-Spider | **Feral Spore-Spider** | `feral_spore_spider` | Fractured crystal sac vents violet dust; torn metal hooks. Social -- swarms. |
| Data-Owl | **Shrike-Owl** | `shrike_owl` | Crest split to twin flat ears, barbed talon cables, cracked clock-face core (same core family as the Saint). Elite. |
| Root-Crab | **Rust-Root-Crab** | `rust_root_crab` | One claw overgrown to a boulder-mace; roots wound tight as tendon. Charges in a straight line. |
| Lichen-Lizard | **Blight-Lizard** | `blight_lizard` | Olive lichen turned bruised violet; tail frays to cable-whips. Basks in the runoff. |

Two larger nodes anchor the arc's back half. **The Bloomwrought
Warden** (`bloomwrought_warden`, CHAMPION) is a Convergence sentinel
the Bloom grafted where it stood -- still walking its patrol around a
vault that stopped answering, never ordered to stand down: a patient
still on duty. **The Sporebound Matriarch** (`sporebound_matriarch`,
BOSS, Gloamwood Depths) is the Bloom's oldest node: a vast brood-mother
that keeps making tenders for a garden whose gardener never came back.
It is not a villain. It is a mother with no one left to raise. Both
are patients, not monsters; the copy must never call them evil.

The Forest Devourer (`void_lord`, world boss in `zone_forest_meadow`)
stays the arc's thesis-monster: roots grew through the hull and made
the machine part of the garden (sec. 5, art bible sec. 8.2). The
Sporebound Matriarch is its kin, deeper and older.

## 6. The player (who you are)

A **tablet-bearer** -- one of the few who can hear the dormant world
answer. Canon in-game: species-faction join at creation; the main
quest chain ("Reach the Nexus Core", canonized from the HUD mock);
dailies like "Siphon Aether" and "Recover Lost Schematics" are the
Waking economy in miniature. Your verb -- wake things -- is also
every system: waypoints, mounts, vehicles, stations, dwellings,
even the house's doorpost clasp.

The three GM classes (gm_akkan/gm_human/gm_synthetic) are
admin-only and NOT diegetic; they have no story presence.

## 7. Story arc skeleton (acts, not quests)

- **Act 1 -- Haven (starter_plains, village_center):** learn the
  tablet; wake your first waypoint; meet the institutions. The
  Horizon Problem is small and personal: wolves, patrols, a lost
  schematic. Ends when the player wakes the Gloamwood gate and sees
  the violet on the far side.
- **Act 2 -- The Bloom (forest_meadow, forest_depths):** the
  corruption arc. Study bloom-touched fauna, trace the runoff,
  meet the Forest Devourer (first world boss). The factions'
  methods diverge here -- Alliance wants to cut it out, Horde to
  ward it, Collective to listen to it. Ends at the mouth of the
  Depths, where the Bloom is thickest and the old elevator down
  still sleeps.

  **Authored lane (2026-11-28):** the corruption reads as a
  five-quest chain out of Haven -- the herbalist studies the
  spiders, then the runoff line; Fenwick's fence line carries it
  down (`quest_study_the_bloom` -> `quest_the_runoff_line` ->
  `quest_break_the_shell` -> `quest_the_silent_stoop` ->
  `quest_cull_the_warden`). Two hordes pace it: **The Bloom Cull**
  (`bloom_cull`, open-world, bossed by the Bloomwrought Warden) and
  **Descent into the Bloom** (`bloom_descent`, dungeon-scoped,
  finishing on the Sporebound Matriarch). The **Bloom Stirs**
  weather event (`bloom_stir`, `active` sky band) stirs the cull in
  the gloam. All of it rides `pack_bloom_act` (the per-shard
  content pack), so an event shard can keep the gloam quiet.
- **Act 3 -- The Question (nexus_central and beyond):** wake the
  Nexus Core itself and learn what the Convergence was for -- and
  what the Silence interrupted. Act 3 is deliberately UNWRITTEN
  beyond its door: the answer is a live design decision (sec. 9),
  and the endgame should be shaped by what players do with the
  network once they hold it.

Multiplayer IS lore: every machine a player wakes stays woken for
everyone. The world's recovery is a scoreboard the whole server
shares.

## 8. Tone & the old-MMO feeling

Warm institutions in a cold world: the inn's lanterns, the smith's
sparks, the academy's patient arch. The twist is that all of it is
slightly alien and slightly asleep. Copy voice: hopeful, practical,
a little reverent. NPCs do not say "powered on" -- they say "woke,"
"answered," "remembered." Nothing is "manufactured" -- it is
"salvaged, grown, or woken." The Bloom is never called evil.

## 9. Mysteries (deliberately open -- do not canonize answers yet)

1. **What caused the Silence?** No war record; halls left mid-task.
2. **Who made the Convergence?** No maker ruins, no maker bodies.
   The Synthetics are evidence without an author.
3. **What is the Nexus Core?** The network's heart -- a machine, a
   council, a person? (The HUD quest says reach it; it does not say
   what answers.)
4. **Why one magenta eye?** The Clockwork Saint's split face and
   the half-lit mandalas imply things wake HALF. Why?
5. **What does the Bloom remember?** It tended the Convergence
   longer than anyone. The Collective thinks it can be spoken with.

## 10. Canon drift log (story-adjacent)

- Village Elder dialogue said "the Darkwood"; zones and renders say
  the Bloom woods. **REVERSED 2026-11-28:** the woods are
  **Gloamwood** (owner call). Earlier this log had resolved the
  Darkwood drift to "Gloomwood" off the zone `.tres` + art, but the
  data ids already used **gloam** (`enemy_gloamwood_stalker`,
  `quest_gloamwood_ledger`, `loot_gloam_*`, `res_gloam_spore`,
  `elixir_gloamward`), and "gloam" is the right register. All display
  strings swept to "Gloamwood" (`zone_forest_meadow`,
  `zone_dungeon_forest_depths`, `village_elder_greeting`, `res_timber`,
  `enemy_thistle_boar`, the `spawn_*` tables, and the web lander). No
  "Gloomwood" or "Darkwood" remains in player-facing copy; ids were
  already correct. See `labs/story-landmark-names.md`.
- Zone descriptions predate the art bible (safe/no-mood tone); when
  rewriting zone copy, use gemini_zones.md moods as canon.
- **"Haven" naming (RESOLVED 2026-11-28).** The starter settlement
  is **"Haven"**, full stop. The story PRD, the art bible, and the
  canonized renders (`gemini_zones.md` sec. 3, "VILLAGE OF HAVEN")
  all say Haven, and every game-data id agrees (`npc_jeweler_haven`,
  `veh_haven_ferry`, `horde_haven_siege`, `quest_wings_over_haven`,
  "Haven Coliseum", "Haven Sandpit", the "Haven Shelf"). The lone
  outlier was the zone display name: `zone_village_center.tres`
  shipped "Easthollow Village", which then leaked into the web
  (achievements chain, lore, lander). Aligned the zone to
  `display_name = "Haven"` and swept the copy. `Meadowhaven`
  (`zone_starter_plains`) is a DIFFERENT place and keeps its name:
  the starter plains, not the village. "Haven" is the settlement;
  "Meadowhaven" is the meadow it sits in.
- **Planet context (2026-11-04).** Act 1's locations stand, but the
  planet-level context is now fixed by `prd-world.md` v2: the capital
  (Nexus Central) is on the **coast**, the starter village is inland
  ~1 km with a **road** to the capital, and the **mountain range**
  rises behind the village. Act 1/Act 2 live on the home continent
  (the ~14 km homeland dome).
- **Bloom-touched bestiary authored (2026-11-28).** Sec. 5's fauna
  table is now real data: the four hostile variants the art renders
  canonized (`gemini_hostile_agents.md`, 2026-09-25) had no
  `data/enemies/` templates at all -- the bestiary stopped at the
  neutrals. Authored `feral_spore_spider`, `shrike_owl`,
  `rust_root_crab`, `blight_lizard`, plus the champion
  `bloomwrought_warden` and the boss `sporebound_matriarch`, their
  shared `loot_bloom_corruption` table, the two hordes, the weather
  event, and `pack_bloom_act`. The corruption medium is fixed: the
  neutral creature, cracked and leaking, magenta where teal was.
- **Two act systems, one word (2026-11-28).** Sec. 7's world arc
  (Haven / The Bloom / The Question) and `data/acts/*.tres` are
  DIFFERENT things that share the word "act". The `.tres` acts are
  the **Concord's Chronicle** -- a reading schedule over the vault
  records (`act_1_the_first_vault`, `act_2_the_unpaid_debt`,
  `act_3_the_trust_audit`), gate-days on the sky calendar. The world
  arc is the campaign's geography. They are not in conflict; they
  are two layers (Chronicle = what the Concord teaches, arc = where
  you walk). Name them apart in copy: "Act II: The Unpaid Debt" is
  a Chronicle chapter, "Act 2, the Bloom" is the zone arc.

## 11. Where canon lives (pointer table)

| Topic | Source |
|-------|--------|
| Visual law, palette, hostility key | `labs/art-direction.md` |
| Render prompts + statuses | `labs/prompts/*.md` |
| Species, classes | `game/data/species/*.tres`, `game/data/classes/*.tres` |
| Factions, politics | `game/data/factions/*.tres` |
| Zones, moods | `game/data/zones/*.tres` + `gemini_zones.md` |
| Boss roster | `game/data/world_bosses/*.tres` + `gemini_bosses.md` |
| Bestiary (hostile + bloom-touched) | `game/data/enemies/*.tres` + `gemini_hostile_agents.md` |
| Hordes, weather events | `game/data/hordes/*.tres`, `game/data/weather_events/*.tres` |
| Per-shard content packs | `game/data/content_packs/*.tres` |
| Institutions (services) | art bible sec. 8.4/8.10; interiors pack |
| Economy flavor | currency star ingots (sec. 8.10), station law |
| Dialogue seeds | `game/data/dialogues/*.tres` (pre-bible; mind sec. 10) |
