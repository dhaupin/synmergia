# Boss Concepts (Gemini brief pack)

> **Goal:** the world-boss roster as visuals. Round 2 produced the
> first boss action render (the violet corrupted boss fighting Cleric
> + Akkan) -- that one is canon as **The Forest Devourer**. This pack
> gives the Forest Devourer a clean standalone study plus the next
> bosses in line, all obeying the hostility key.
>
> **Canon anchors:** `game/data/world_bosses/world_boss_forest_void_lord.tres`
> (The Forest Devourer, spawns zone_forest_meadow), plus the enemy
> templates in `game/data/enemies/`.

---

## 0. STYLE LOCK (paste at the top of EVERY prompt below)

```
Stylized cyber-organic fantasy concept art, inked outlines with
cel-shaded flats and painted texture. A world of ancient dormant
symbiotic technology overgrown by nature: geometric circuit forms
wrapped in roots, moss, and mycelium. Desaturated grey-green base
palette (#c0c0c0 stone, #404040 shadow, #202020 dark) with three
semantic accent colors ONLY: pale teal/cyan (#80c0c0) for dormant or
waking technology, warm gold (#c0a060) for active converged
technology, violet (#8060c0) exclusively for mycelium and arcane
magic. Hot magenta-pink is reserved EXCLUSIVELY for the glowing eyes
and small glowing cracks of corrupted creatures -- it never appears
anywhere else. No photorealism, no low-poly look, no neon cyberpunk
aesthetic. Clean white-grey presentation background for studies,
16:9 with a thin margin, hand-lettered style labels (short labels
only, no paragraphs of text).
```

**IMPORTANT TEXT RULE:** render ONLY the exact label words listed at
the end of the prompt. Do NOT render filenames, `.tres` extensions,
hex codes, or any other text -- readable wrong words are drift.
Decorative glyph scribbles are fine.

---

## 1. The Forest Devourer (standalone boss study)

The canon first boss. From the rendered action study: a corrupted
agent-core colossus, roughly humanoid but animal-first, its stone-grey
geometric hull cracked open and overgrown with a bright violet
mycelium mantle that vents spore-clouds. Hexagonal plate shards
float where armor has burst. Magenta eyes, magenta glow-lines in the
cracks. Massive claw limbs, cable-tendons. Spore-Spiders (small,
violet-capped, magenta-eyed) swarm at its feet.

**Prompt:**

```
[STYLE LOCK]

Full-body boss study, front three-quarter view on a clean white-grey
background: a colossal corrupted creature, twelve meters tall. Its
body is a cracked geometric stone hull (dormant tech gone wrong),
wrapped in a bright violet mycelium mantle that pours spore-dust.
Hexagonal plate shards drift around burst joints, tethered by black
cable-tendons. Two hot magenta glowing eyes, thin magenta glow-lines
inside the hull cracks. Enormous claw limbs rooted in a slab of
broken ground it drags along. A small swarm of spore-spiders
(violet-capped, magenta-eyed) circles its feet. Silhouette must read
as one animal-shaped mass, not a mech. Ground shadow, epic scale.

Labels: "THE FOREST DEVOURER" only. No other text.
```

---

## 2. Boss trio sheet (next bosses in line)

One sheet, three silhouettes. These are future world bosses; names
below are the working canon titles (data files follow later when
implemented -- keep titles as listed, they will anchor the .tres).

**Prompt:**

```
[STYLE LOCK]

Boss sheet titled "SYNMERGIA: DORMANT COLOSSI", three full-body boss
studies on one white-grey background, even spacing, same scale,
distinct silhouettes:

1. THE FOREST DEVOURER: as the standalone study -- cracked geometric
   stone hull, violet mycelium mantle, drifting hex shards, magenta
   eyes, spore-spiders at its feet. Quadruped-rooted stance.

2. THE CLOCKWORK SAINT: a humanoid colossus of cracked porcelain-
   white plate over dark alloy, a huge fractured clock-face core in
   its chest (same design family as the Shrike-Owl's cracked clock
   core), ringed by slow orbiting seconds-glyph shards (tiny
   geometric ticks, not numerals). Teal residual glow in the intact
   circuitry, one magenta eye, one hollow socket. Kneeling, rising.

3. THE MOSSBOUND HERALD: a wide, squat tortoise-like fortress
   creature whose shell is an entire overgrown rooftop-garden ruin
   (trees, an archway, a tiny dormant bell tower growing from its
   back). Calm teal circuitry, NO magenta -- it is neutral, an
   ambulatory ruin that only retaliates. Moss waterfall from the
   shell rim.

Labels: "THE FOREST DEVOURER", "THE CLOCKWORK SAINT", "THE MOSSBOUND
HERALD", and the sheet title. No other text.
```

**Accent discipline for this sheet:** the Devourer carries violet +
magenta (corrupted); the Saint carries teal + a single magenta
element (half-corrupted); the Herald is teal + moss only (neutral).
The sheet demonstrates the full hostility spectrum in one image.

---

## Rendering checklist (for after generation)

- [ ] Magenta ONLY on eyes/cracks of corrupted creatures, <1% of frame
- [ ] Violet only as mycelium mantle/spore-dust (corruption medium)
- [ ] Neutral bosses (Herald) carry zero magenta
- [ ] Animal-first silhouette, never "mech with fur"
- [ ] The Devourer matches the rendered action study (same hull
      design family as the Shrike-Owl's clock-core agents)
- [ ] Drop in Drive, attach favorites for critique
