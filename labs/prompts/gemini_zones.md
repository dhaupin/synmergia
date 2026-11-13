# Zone Establishing Shots (Gemini brief pack)

> **Goal:** wide 16:9 establishing shots for the authored zones, for
> loading screens, zone-entry splash, and the world map. Every prompt
> anchors to a real zone id in `game/data/zones/` (or a species
> home_zone) so the art and the map agree.
>
> **Canon anchors:** `zone_starter_plains`, `zone_forest_meadow`
> (Gloamwood Meadow), `zone_village_center` (Village of Haven),
> `zone_dungeon_forest_depths`; species home zones `dark_highlands`
> (Akkan) and `nexus_central` (Synthetic).

---

## 0. STYLE LOCK (paste the full paragraph into EVERY prompt -- never a placeholder token)

```
Stylized cyber-organic fantasy concept art, inked outlines with
cel-shaded flats and painted texture. A world of ancient dormant
symbiotic technology overgrown by nature: geometric circuit forms
wrapped in roots, moss, and mycelium. Desaturated grey-green base
palette (#c0c0c0 stone, #404040 shadow, #202020 dark) with three
semantic accent colors ONLY: pale teal/cyan (#80c0c0) for dormant or
waking technology, warm gold (#c0a060) for active converged
technology, violet (#8060c0) exclusively for mycelium and arcane
magic. No photorealism, no low-poly look, no neon cyberpunk
aesthetic. Wide 16:9 cinematic establishing shot, thin white margin,
hand-lettered style label (short label only, no paragraphs).
```

**IMPORTANT TEXT RULE:** render ONLY the exact zone label word given
at the end of each prompt. Do NOT render filenames, hex codes, or any
other text. One label per image.

---

## 1. Starter Plains (the tutorial mood)

**Prompt:**

```
[STYLE LOCK]

Wide establishing shot of rolling green-grey plains under a pale
high sky. Megaflora: giant dull-metal seed pods half-buried like
sleeping whales, grass growing over their seams. A few dormant
waypoint stones (short geometric pylons, faint teal circuit lines)
mark a winding dirt path. Distant herd of neutral Root-Crabs
grazing, calm. No corruption, no magenta. Warm, safe, slightly
lonely morning light.

Labels: "STARTER PLAINS" only. No other text.
```

> **Status:** rendered + canonized 2026-09-25 (labs/art-direction.md
> sec. 8.11). Drift ruling: one gold-seamed pod + one violet-veined
> pod -- acceptable variety, no magenta.

---

## 2. Gloamwood Meadow (corruption at the treeline)

The Forest Devourer's zone. Mist, grey wolves near the treeline,
violet corruption runoff.

**Prompt:**

```
[STYLE LOCK]

Wide establishing shot of a misty meadow at the edge of a dark
conifer forest. Pale mist pools between leaning trees. Violet
mycelium glow seeps from the forest edge in thin veins; a small
stream runs violet-tinted (corruption runoff) under a mossy stone
bridge. Near the treeline, a pack of grey wolves watches, calm but
alert. One dormant waypoint stone in the foreground, teal circuits
barely lit. Ominous but beautiful; the violet veins suggest
something large sleeps deeper in.

Labels: "GLOOMWOOD MEADOW" only. No other text.
```

> **Status:** rendered + canonized 2026-09-25 (sec. 8.11), incl. the
> violet veins climbing the trunks and the bridge stream.

---

## 3. Village of Haven (the one warm zone)

Player/social hub. The one place allowed to feel warm and lived-in.

**Prompt:**

```
[STYLE LOCK]

Wide establishing shot of a small fortified village at dusk,
built against and inside a ring of dormant megastructure: houses
clustered in the lee of a colossal fallen machine limb, its metal
overgrown with moss and windowed with new wooden shutters. Warm
amber window-light and fire-pit glow (the one permitted warm scene
in the region). An Aether-Conduit terminal (teal-glowing console)
stands at the village square beside a well. Villagers and an Akkan
guard move between buildings. Smoke wisps, laundry lines, quiet
hope. Faint teal circuitry traces across the great fallen limb.

Labels: "VILLAGE OF HAVEN" only. No other text.
```

> **Status:** rendered + canonized 2026-09-25 (sec. 8.11). Canon
> addition: hubs may field more than one Aether-Conduit (two
> rendered).

---

## 4. Forest Depths (dungeon entrance)

**Prompt:**

```
[STYLE LOCK]

Wide establishing shot looking down a huge forest ravine. Old
growth canopy closes overhead; roots wrap the broken geometric
walls of a sunken structure descending into darkness. Teal
circuit-veins pulse faintly along the descending steps, guiding
down. Violet mycelium clusters thicken with depth until the
bottom disappears into spore-haze. A single Shrike-Owl silhouette
circles in the shafts of light above. Damp, deep, inviting.

Labels: "FOREST DEPTHS" only. No other text.
```

> **Status:** rendered + canonized 2026-09-25 (sec. 8.11); the
> circling owl rendered as a generic bird silhouette -- fine.

---

## 5. Dark Highlands (Akkan home)

**Prompt:**

```
[STYLE LOCK]

Wide establishing shot of highland moor under a bruised sky:
black stone torsi and shattered monolith fields, floating rock
islets with hanging moss and dormant orb machines, thin
waterfalls dropping from the islets. Akkan cairn-markers and
angular dark-bronze banners with gold trim line a ridge path.
Ember-orange sigils burn slowly on the largest monolith (Akkan
sigil color only). Cold wind, monumental silence, martial and
ancient.

Labels: "DARK HIGHLANDS" only. No other text.
```

> **Status:** rendered + canonized 2026-09-25 (sec. 8.11); ember
> sigils stayed clean of teal/violet bleed.

---

## 6. Nexus Central (Synthetic home)

**Prompt:**

```
[STYLE LOCK]

Wide establishing shot of a vast dormant machine hall turned
living ecosystem: a cathedral-scale interior where geometric
server-monoliths rise through open shafts of grey daylight, all
wrapped in climbing vines and moss. Synthetics move on catwalks
between the monoliths; soft teal circuitry wakes in patchy grids
where they pass. A central spire of stacked Agent Core emblems
rises through the middle, half its mandala lit teal, just
beginning to catch gold at one tip. Cable-roots drape from the
ceiling like vines. Serene, immense, half-awake.

Labels: "NEXUS CENTRAL" only. No other text.
```

> **Status:** rendered + canonized 2026-09-25 (sec. 8.11); spire
> rendered with gold star-crowns over the teal base mandala.

---

## Rendering checklist (for after generation)

- [x] Round 4 rendered 2026-09-25: 6/6 on-model, zero magenta,
      labels clean (sec. 8.11)
- [ ] One label per image, spelled right, no extra text
- [ ] Zone mood matches its data: Starter Plains safe/lonely,
      Gloamwood ominous/violet-veined, Haven the only warm scene,
      Depths descending/teal-guided, Highlands martial/ember,
      Nexus serene/half-awake
- [ ] No magenta anywhere (none of these zones are corrupted zones;
      violet only in Gloamwood and Depths as mycelium)
- [ ] Same ink weight and 16:9 framing as the concept set
- [ ] Drop in Drive, attach favorites for critique
