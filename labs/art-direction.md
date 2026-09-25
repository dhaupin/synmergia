# Synmergia Art Direction (Style Bible)

> **Status:** CANON. Every image-generation prompt, UI skin, zone
> backdrop, and content .tres must pass through this document. When a
> generated image contradicts this bible, the bible wins (or we amend
> it deliberately -- never silently).
>
> **Source of truth:** the Gemini world-building session concept set
> (26 sheets, Sep 2026, Drive: "Synmergia Concept Art (Shared)") plus
> the shipped logo pack in `game/assets/branding/`. Palette hexes
> below are measured from the set (pixel analysis), not eyeballed.
>
> **Round 2 (2026-09-25):** 23 renders from the `labs/prompts/` packs
> critiqued and canonized (species/class sheets, hostile agents,
> service-NPC interiors, key art). Palette audit across the full 50-
> image set re-verified the accent semantics; findings are in sections
> 8-10. The first completed sheets render at ~1400x768; keep 16:9.

---

## 1. The one-line pitch

Synmergia is an **unpowered world**: ancient symbiotic technology went
dormant, nature overgrew it, and explorers with glowing tablets walk
the ruins waking things up. Everything in the art serves that verb:
**find the dormant thing, reactivate it.**

## 2. Style lock (do not drift)

| Element | Rule |
|---------|------|
| Rendering | Stylized cyber-organic ("Option A" of the decision sheet). Inked outlines, celshaded flats, painted texture. NOT photoreal, NOT low-poly, NOT brutalist. |
| Geometry | Cyber forms are **geometric** (hexes, circuit lattices, star cores); organics are **overgrown** (roots, mycelium, moss) wrapping the geometry. The hybrid seam is the money shot. |
| Cameras | Wide establishing shots for zones (16:9), tight object studies for props/fauna, front-facing sprite sheets for characters. |
| Aspect | Zone/env sheets: 16:9, 768 px tall (matches the existing set). |

## 3. Color system (measured from the set)

Base world is desaturated grey-green; **accents are semantic, not
decorative.** Three accent domains, consistently used across all 26
sheets:

| Accent | Hex (measured) | Meaning | Appears on |
|--------|----------------|---------|-----------|
| **Teal / cyan** | `#80c0c0` highlights, `#204040` deeps | DORMANT + residual tech; things that can be woken | waypoint panels, spore glows, agent eyes, circuit tracery |
| **Gold** | `#c0a060..c0a080` family | ACTIVE / converged tech; premium, ceremonial | Convergence Spire, active circuits, currency, legendary items |
| **Purple / violet** | `#8060c0` family | MYCELIUM + arcane ONLY | fungal networks, psionic effects -- never for tech or UI |

Supporting neutrals (the actual workhorses): `#c0c0c0` (stone/steel
light), `#808080`, `#404040`, `#202020` (shadows), olive-khaki
`#a0a080` (dry flora), red-brown `#604040` (rust, cinder, dried blood).

**UI consequence:** teal = interactive-but-dormant, gold =
reward/prestige/active, purple = arcane slots only. The game's existing
`accent_gold` UI token stays; teal becomes the interactive accent as
UI skins land. Purple never touches buttons.

**Zone mood rule:** one warm zone per region cluster max (the Rust-Eater
colony is the current warm outlier -- orange/salvage); everything else
stays cool so warm scenes pop.

## 4. The iconography

- **The Agent Core** (shipped logo emblem): a geometric star with a
  pale core. In-world it is the mark of the Convergence -- embed it on
  doors (Concept 4), waypoints, UI chrome, faction seals.
- **Circuit tracery** = the world's "writing." Patterns glow teal when
  dormant-adjacent, gold when active. Text-shaped glyphs are decorative
  only (and per the concept sheets, often gibberish -- in-game we treat
  tracery as unreadable script, never real text).
- **Tablets:** every explorer carries a glowing tablet (the player's
  scanner/interface diegetically justified).

## 5. Fauna convention: "agents"

Cyber-organic creatures are named `<Substance>-<Animal>`:

- Data-Owl, Spore-Spider, Root-Crab, Lichen-Lizard, Mycelial-Mantid,
  Luminous-Lemur (canon so far).
- Neutral/dormant variants read calm (glassy, pale); hostile/corrupted
  variants carry the visual key (magenta eyes, cracked shells,
  leaking spores) -- designed + canonized 2026-09-25, see sec. 8.7
  and `labs/prompts/gemini_hostile_agents.md`.
- Anatomy rule: animal silhouette first, tech second (shell plating,
  crystal sacs, cable tails). Never a robot wearing fur.

## 6. Known gaps -> brief coverage

Every gap now has a brief; render + critique closes them:

1. **Akkan + Synthetic deep-study sheets** -- briefs in
   `labs/prompts/gemini_species_classes.md` sec. 6-7 (Human done,
   sec. 8.6; three-species lineup canon, sec. 8.9).
2. **Individual class hero shots** -- DONE, canonized (sec. 8.10);
   15 more classes can follow the same brief template if wanted.
3. **Zone establishing shots** -- briefs ready in
   `labs/prompts/gemini_zones.md` (Gloomwood Meadow, Starter Plains,
   Village of Haven, Forest Depths, dark highlands, Nexus Central).
4. **Interiors** -- DONE: service shops (sec. 8.4) + inn/dwelling/
   gateway canonized (sec. 8.10).
5. **UI mockups** -- icons + Aether-Conduit menu DONE (sec. 8.10);
   HUD skin re-render pending (dropped render).
6. **Bosses** -- briefs in `labs/prompts/gemini_bosses.md`
   (Devourer standalone + Clockwork Saint + Mossbound Herald); the
   Devourer action study is already canon (sec. 8.2).

## 7. Prompt pipeline

Prompt briefs are staged in `labs/prompts/` for the human to run
through the image generator (Gemini). Naming:
`gemini_<subject>.md`. Each brief carries the style-lock block so
renders come back on-model. Finished art gets critiqued against this
bible, then either iteration or canonization (a place in the docs +
data files).

## 8. Round 2 canonization (2026-09-25)

Findings from the 23-render drop, now canon:

### 8.1 The hostility key works in practice

The Shrike-Owl battle study (owl with cracked clock-face core, violet
wing swirls, magenta eyes; Akkan duel partner; Spore-Spider swarm
underfoot) and the violet corrupted boss fight (Cleric + Akkan vs the
Forest Devourer) both carry the key correctly: magenta reads ONLY on
hostile eyes/small accents, violet stays spore/mycelium, teal keeps
serving dormant tech. Pixel audit across all 50 sheets: magenta never
exceeds ~0.9% of frame area and appears only on corrupted-agent
renders. The key is load-bearing -- keep it in every future brief.

### 8.2 Corrupted violet boss = the Forest Devourer

The large violet-mantled corrupted boss (spore-cancered stone hull,
hex-plate, claw limbs, magenta eyes, Spore-Spider minions) is the
first boss visual: **The Forest Devourer** (`forest_void_lord`,
`game/data/world_bosses/world_boss_forest_void_lord.tres`, spawns in
zone_forest_meadow). Design traits now canon for this boss: violet
corruption mantle + cracked geometric hull + magenta eyes + rodent-
swarm add waves. Poison/violet waterfalls in its meadow = corruption
runoff (a Gloomwood tell).

### 8.3 AETHER-CONDUIT is the in-world terminal term

Three of four interiors independently labeled the glowing console
"AETHER-CONDUIT" -- adopt it: **an Aether-Conduit is the player-facing
terminal/kiosk** (teal wake-machinery that explorers use to access
services). Future UI/interior briefs and any NPC terminal art use this
term. It appears in the vault, academy, blacksmith, and storekeeper
scenes.

### 8.4 Service interiors -> services (canon mapping)

| Interior sheet | Canonical service | Canon set dressing |
|----------------|-------------------|--------------------|
| Vault ("SECURE VAULT ACCESS") | VaultService | octagonal door with Agent Core mandala, root-overgrown shelving, valuation counter, asset-deposit chute |
| Skill Academy ("SKILL UPGRADES") | SkillAcademyService | armored skill-dispenser arch, training dummy, stat-reset plinth, specialty alcove |
| Blacksmith ("BLACKSMITH") | BlacksmithService | agent-core furnace head, anvil, hex shelving, assistant hauling cable coils |
| Storekeeper ("SUPPLIES & CONSUMABLES") | vendor/storekeeper | counter-and-conduit shop, salvage-gear rack, trade-goods shelving |

Shared interior grammar (canon): every shop is a dormant machine
wrapped in roots + mycelium, one Aether-Conduit console, one or two
human/Akkan staff, shelves overgrown but functional. Steam wisps OK.

### 8.5 Duel key art (Akkan vs Synthetic) is the PvP face

The Akkan-vs-Synthetic floating-island duel with the SYNMERGIA
wordmark is the standing PvP/versus key art. Akkan war-plate + gold
trim + slab-sword and shield; Synthetic lean ceramic frame, cable-
tail, teal arcs. Floating islets with hanging moss + dormant orb
machines are the background grammar for highlands vistas.

### 8.6 Human species sheet is canon; label drift rules reinforced

"THE HUMAN SPECIES" sheet (female + male explorer head studies,
explorer default scavenger form, canon-anchor head row) is the Human
reference. Two drift artifacts to keep fighting in briefs:

- **Anchor filenames became labels:** the bottom row was labeled
  `species_human.tres` / `species_akkan.tres` / `species_synthetic.tres`
  -- Gemini baked the brief's anchor filenames as visible text. Future
  briefs must not include filenames in the rendered-label instruction.
- **Gibberish marks remain** ("MIY WORDMARK" on the storekeeper
  sheet, sigil scribbles on the owl study, rune-slab scribbles).
  Standing rule unchanged: baked text is decorative; only the words
  enumerated in the brief's "Labels" line are load-bearing, and any
  label not in that list is a known artifact, not lore.

### 8.7 The bestiary sheet is canon (visual critique pass)

All four hostile variants landed on-model; seeing the pixels confirms
what the palette audit could only imply:

- Magenta appears ONLY as eyes on every variant (plus the feral
  spider's mouth-cluster) -- never on plating, lichen, or wings.
- Violet stays the corruption MEDIUM: the spider's burst crystal sac
  + spore clouds, the Blight-Lizard's bruised patches. Wing swirls
  stayed grey-green ink, not violet.
- Neutral forms keep glassy teal accents and calm poses; each pair
  clearly reads as the same creature. Silhouettes stayed animal-first
  (the crab keeps its boulder-mace claw; the lizard keeps cable
  frays on the tail).

Design locks for reruns: Shrike-Owl = laid-flat twin crest ears,
barbed talon cables, magenta eye-slit. Rust-Root-Crab = split
boulder-mace claw, torn rusted plating, root tendons. Blight-Lizard
= taut long limbs, bruised-violet patches, triple cable-fray tail.
Feral Spore-Spider = hunched bristle, burst violet sac, hooked
metal legs. These four are the enemy bestiary reference for future
zone-population art and AI/agent sprite work.

### 8.8 Trio hero shot is canon (co-op key art)

The dawn canyon shot: hooded Human raising the teal tablet, the
slab-sword Akkan, the pale-ceramic Synthetic with teal spine core,
all facing the overgrown Convergence Spire door whose mandala is
just catching gold at the center, Data-Owls circling. It has the
money shot (geometry-wrapped-in-organic seam), the dormant-to-active
gold transition, and the quiet hope the brief asked for. Use it as
co-op/loading key art alongside the duel (sec. 8.5).

### 8.9 Class sheets + species lineup canonized (visual critique pass)

All three class sheets and the species lineup landed on-model:

- **Human classes:** Warrior (crimson tabard, teal-mandala shield),
  Guardian (teal convergence studs), Marksman (root-grown longrifle),
  Sorcerer (violet thread ONLY + violet sigil ring), Cleric (gold
  halo-arch), Temporalist (orbiting teal tablets + seconds-glyph
  ring, no numerals, rendered larger) -- exactly as briefed.
- **Akkan classes:** shared face/skin/ember eyes consistent across
  all six; Bulwark's shield is a dormant Convergence door-seal waking
  gold at its center (the single best tech-seam in the whole set);
  Seer reads floating ember sigils; Shaman's talismans are carved
  tags on cable; Attacker in a full sprint.
- **Synthetic classes:** Conduit is the icon -- the Agent Core
  star-core rendered diegetic on a character's chest, teal arcs
  between the fingertips. Exploiter's hooked gauntlet + stolen gold
  circuit patches; Overclocker's gold heat-sink fins + cracking
  ground; Psion's violet mantle grown INTO the plating + violet
  shards; Tracker's folding sensor array + woven-cable cloak;
  Warden's teal hex barrier + the Luminous-Lemur cameo.
- **THE THREE SPECIES lineup** (Human explorer / Akkan warrior /
  Synthetic Conduit + two-variant head rows per species) is the
  species-select reference; faces match the class sheets.

Drift found in this pass, ruled on (do not re-canonize):

- **Marksman rendered twice** on one Human-classes variant (7
  figures, grid permutation); the second variant sheet is the clean
  six-distinct-class render and is the canon reference. Rule: six
  DISTINCT classes per sheet.
- **"RUNEBLADE" label** -- data says Runesmith
  (`class_akkan_rune.tres` display_name). The .tres wins; briefs now
  label RUNESMITH.
- **"[STYLE LOCK]" token leaked as literal header text** on the
  Akkan sheet (and "[HAND-LETTERED STYLE]" on Human). New
  convention: paste the EXPANDED style-lock paragraph into the
  prompt, never a placeholder token -- all briefs updated.
- **Stray annotation words** ("'Default'", "Tree-Roots",
  "Luminous-Lemur", "Variant Helmet/Hair") -- decorative per
  sec. 8.6, ignore.

### 8.10 Round 3 canonization (2026-09-25, class heroes + interiors/UI)

Eight renders reviewed visually (the HUD mock was dropped by the
chat client -- re-render pending). Headline: **the text rules held.**
Every visible label is correctly spelled (RUNESMITH rendered right
where round 2 said RUNEBLADE); the only baked text left is decorative
rune-glyph scribble, which the canon already treats as unreadable
script. The hardened style lock is doing its job.

Class heroes -- all three on-model and canonized as the
tooltip/class-select key art:

- **Temporalist:** fractured clock-motif pauldron (teal clock face),
  two teal tablets orbiting the raised hand, seconds-glyph ring with
  tiny ticks (no numerals), closed eyes, root-pried causeway, dormant
  spires in haze, left third UI-clean.
- **Conduit:** Agent Core star in the chest, teal arcs, cable-tail,
  and the floor wake-ring -- the circuit grid lighting teal in a
  spreading circle around its feet with moss retreating is now the
  canonical "synthetic wakes the ground" gesture.
- **Runesmith:** ember-orange rune-tablet blade (glyph scribble
  decorative), sigil-tags on braided cable, one tag free and
  igniting mid-air with a flame trail -- exactly as briefed.

Interiors -- the remaining rooms are canon:

- **Gateway chamber:** colossal ring door with the Agent Core star
  and a maze-pattern mandala, teal dormant, ONE segment lit gold; a
  hand touches the ring with a teal tablet (the activation verb,
  rendered). Two vine-wrapped headless sentinel statues flank the
  approach; teal guide-rungs descend the steps; mist under the seam.
  This frame is a pitch-shot candidate for the store page.
- **Echo Plaza Inn:** ribcage machine hall strung with warm amber
  lanterns (the one warm room), pigeonhole locker wall (player
  mail/storage), a DARK dormant Conduit terminal at the bar
  (unlit-screen state -- that dormant look is the reference for
  powered-off terminals), Synthetic sentinel doorman, stair to
  rooms. Drift note: one patron rendered with saturated purple
  skin -- Akkan skin stays the desaturated #a0a0c0 family.
- **Dwelling:** cot, workbench with a LIT teal Aether-Conduit
  panel, tool wall, chest, pinned sketch, chipped mug, laundry
  line, and the root-trained coat hook realized literally. Drift
  note: indoor violet moss patches read as damp/haunted -- rule:
  violet indoors means moisture and neglect; keep it out of cozy
  rooms on purpose.
- **Gateway violet moss** (wall clusters) is acceptable as mycelium
  overgrowth but stays out of focus zones.

UI canon (first real chrome in the set):

- **Item icon sheet:** all 16 briefed icons rendered and canonized
  as the inventory icon reference. Currency is now canon: **gold
  ingots stamped with the Agent Core star** (diegetic emblem on
  money). The rune-tablet slab-sword icon ties the Runesmith blade
  into the icon family; the mycelium satchel is the sole violet
  item, as briefed.
- **Aether-Conduit service menu:** the six-tile dark-graphite menu
  with stone-and-root border is the service-hub reference. Gemini
  named the tiles -- adopt them: VAULT SERVICE, GUILD REGISTRY,
  CONVERGENCE CHRONICLES (the gold/active tile -- canon as the
  lore/journal service), SMITHING SERVICES, MARKET EXCHANGE,
  WAYPOINT NETWORK. Working service mapping: VaultService,
  GuildService, codex/achievements, BlacksmithService,
  TradeService/market, WaypointService.

### 9. Engine-facing next steps (from Round 2 + 3 art)

When wiring art into the game, these are the first touchpoints:

1. Species-select card art <- Human species sheet + trio lineup
2. Class-select card art <- the three class sheets (18 classes);
   hero shots (Temporalist/Conduit/Runesmith) for the spotlight pane
3. Service NPC interior backdrops <- the seven interior sheets
   (vault/academy/blacksmith/storekeeper/inn/dwelling/gateway)
4. World-boss intro splash <- Forest Devourer battle study
5. Loading-screen art <- Akkan-vs-Synthetic duel (PvP), trio hero
   shot (co-op), Gateway chamber (zone transitions)
6. Inventory UI <- 16-icon reference sheet; currency renders as
   star-stamped ingots
7. Service-hub screen <- Aether-Conduit menu (six named tiles)
8. HUD skin <- pending re-render (dropped from the chat batch)

### 10. Palette audit method (reproducible)

The measured palette is re-derived per drop with a small pixel-count
pass (PIL thumbnail 480px, semantic buckets for teal/gold/violet/
magenta against the hex families in sec. 3). Rule of thumb from the
50-sheet audit: teal should dominate (10-27% of frame on tech-forward
sheets), gold stays low single digits except ceremonies/vault/duel,
violet 0-11% and only where mycelium/arcane is the subject, magenta
<1% and only on corrupted agents. A drop that breaks these bands is
style-drift -- iterate before canonizing.
