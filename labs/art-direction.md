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
  variants need a visual key (magenta-thread eyes, cracked shells,
  leaking spores) -- NOT YET DESIGNED (see prompts).
- Anatomy rule: animal silhouette first, tech second (shell plating,
  crystal sacs, cable tails). Never a robot wearing fur.

## 6. Known gaps (priority for future prompts)

1. **Akkan + Synthetic species sheets** -- Human is done (see sec. 8.6);
   Akkan and Synthetic deserve their own head-study/explorer sheets.
2. **Individual class hero shots** -- the 18-class sheets work as
   lineups; leads (Temporalist, Conduit, Runesmith) want single-figure
   key art for ability tooltips and class-select.
3. **Zone establishing shots** matching authored zones -- briefs ready
   in `labs/prompts/gemini_zones.md` (Gloomwood Meadow, Starter Plains,
   Village of Haven, Forest Depths, dark highlands, Nexus Central).
4. **Interiors not yet covered:** inn (Echo Plaza), dwelling/house
   interior, gateway chamber.
5. **UI mockups** -- HUD skin, inventory icons, and the Aether-Conduit
   player-facing terminal chrome (see sec. 8.3).

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

### 9. Engine-facing next steps (from Round 2 art)

When wiring art into the game, these are the first touchpoints:

1. Species-select card art <- Human species sheet + trio lineup
2. Class-select card art <- the three class sheets (18 classes)
3. Service NPC interior backdrops <- the four interior sheets, keyed
   by service (VaultService/SkillAcademyService/BlacksmithService/vendor)
4. World-boss intro splash <- Forest Devourer battle study
5. Loading-screen art <- Akkan-vs-Synthetic duel (PvP) and trio hero
   shot (co-op)

### 10. Palette audit method (reproducible)

The measured palette is re-derived per drop with a small pixel-count
pass (PIL thumbnail 480px, semantic buckets for teal/gold/violet/
magenta against the hex families in sec. 3). Rule of thumb from the
50-sheet audit: teal should dominate (10-27% of frame on tech-forward
sheets), gold stays low single digits except ceremonies/vault/duel,
violet 0-11% and only where mycelium/arcane is the subject, magenta
<1% and only on corrupted agents. A drop that breaks these bands is
style-drift -- iterate before canonizing.
