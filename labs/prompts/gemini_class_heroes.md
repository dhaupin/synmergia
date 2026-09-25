# Class Hero Shots (Gemini brief pack)

> **Goal:** single-figure key art for the class leads -- the images
> that sit behind ability tooltips, class-select spotlights, and
> marketing. The 18-class sheets already exist (canon,
> labs/art-direction.md sec. 8.9); this pack renders the three
> flagship classes at full detail, one per image, 16:9 with room for
> UI overlay on the left third.
>
> **Canon anchors:** `game/data/classes/class_human_temporalist.tres`,
> `class_synthetic_conduit.tres`, `class_akkan_rune.tres`
> (display_name "Runesmith" -- label it RUNESMITH, Gemini has
> rendered "RUNEBLADE" before).

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
aesthetic. Single-figure cinematic key art, 16:9 with a thin white
margin, subject placed in the right two-thirds of the frame so UI
can overlay the left third. One short hand-lettered label only.
```

**IMPORTANT TEXT RULE:** render ONLY the label word given at the end
of the prompt. No filenames, no other text.

---

## 1. Temporalist (Human flagship)

**Prompt:**

```
[STYLE LOCK -- expanded]

Cinematic single-figure key art of a TEMPORALIST: a calm human
time-weaver in a sand-beige longcoat with a fractured clock-motif
pauldron, standing three-quarter view on a shattered stone causeway
in an overgrown canyon. Twin glowing teal tablets orbit one raised
hand at different heights; a slow ring of floating seconds-glyphs
(tiny geometric ticks, NOT readable numerals) encircles the figure
at chest height. One boot on a broken conduit pipe; thin roots have
pried the causeway stones apart. Closed eyes, absolute control.
Morning haze, pale grey-green sky, distant dormant spire towers.
Left third of the frame stays open ground for UI overlay.

Labels: "TEMPORALIST" only. No other text.
```

---

## 2. Conduit (Synthetic flagship / the species icon)

**Prompt:**

```
[STYLE LOCK -- expanded]

Cinematic single-figure key art of a CONDUIT: an elegant humanoid
machine, the herald-frame of the Synthetic species, standing in a
half-woken machine hall where server-monoliths vanish into vines
above. Matte pale-ceramic and dark-alloy plating, smooth
featureless faceplate with two soft teal light eyes, the Agent Core
star emblem glowing teal in its chest. Energy arcs between
fingertips of both raised hands; the floor's circuit grid lights
teal in a spreading ring around its feet, moss retreating from the
wake. Thin cable-tail coiled behind. Left third of the frame stays
open (archway and mist) for UI overlay.

Labels: "CONDUIT" only. No other text.
```

---

## 3. Runesmith (Akkan flagship)

**Prompt:**

```
[STYLE LOCK -- expanded]

Cinematic single-figure key art of a RUNESMITH: an Akkan
rune-specialist on a dark-highlands tor under a bruised sky,
drawing an inscribed slab-sword whose rune-tablet blade glows
ember-orange (Akkan sigil color only -- no teal, no violet on the
sigils). Angular dark-bronze war-plate with worn gold trim and
carved clan sigils, grey-violet skin, deep-set ember eyes, dark
braids. Detonation sigil-tags dangle from the belt on braided
cable; one hovers free, igniting. Floating rock islets with
hanging moss and a dormant orb machine in the background. Cold
wind-blown grass, monumental silence. Left third open for UI.

Labels: "RUNESMITH" only. No other text.
```

---

## Rendering checklist (for after generation)

- [ ] One label per image, spelled right
- [ ] Subject in the right two-thirds; left third overlay-clean
- [ ] Temporalist: teal tablets + glyph ticks, NO numerals
- [ ] Conduit: star-core chest emblem, teal arcs, no violet
- [ ] Runesmith: ember-orange sigils only, no teal/violet bleed
- [ ] Same ink weight as the class sheets; figures on-model
- [ ] Drop in Drive, attach favorites for critique
