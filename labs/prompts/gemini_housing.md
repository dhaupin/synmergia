# Player Housing & Dwellings (Gemini brief pack)

> **Goal:** house exteriors by tier and the construction grammar that
> makes them feel like one system. Interiors are partially canon
> (the Dwelling interior, sec. 8.10); this pack covers the outside,
> the tiers, and the placeable-furniture feel.
>
> **Canon anchors:** `game/data/dwellings/` items are placeable
> furniture (Stone Fireplace, Wooden Chair -- `is_placeable`,
> `dwelling_category` lighting/furniture); DwellingService handles
> plots; the canon interior (cot, workbench Conduit, root coat hook)
> sets the lifestyle. The inn (sec. 8.10) is the communal ceiling of
> what housing aspires to.

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
aesthetic. Wide 16:9 establishing shots with a thin white margin;
hand-lettered style labels only, no paragraphs of text. Render ONLY
the exact label words given -- no other text.
```

**Housing color law:** homes are timber + salvage + moss with WARM
amber window-light (housing joins the inn as warm-allowed); teal
appears only in wake-clasps, the door-side Aether-Conduit post, and
tiny address glyphs; gold only on the master-tier finial. Violet and
magenta forbidden on all structures.

---

## 1. The Three Tiers (one sheet, same plot)

**Prompt:**

```
[STYLE LOCK -- expanded]

Housing sheet titled "SYNMERGIA: HOMESTEADS", three small house
exteriors in a row on identical grass plots, same scale, dusk
lighting with warm amber window-light in all three:

1. CLAIM (tent): a timber-frame salvage-canvas tent, rope seams,
   a rolled bedroll visible through the flap, a single lantern
   hook, a small teal wake-clasp on the doorpost (claim marker).

2. COTTAGE (timber): a one-room timber cottage with a moss sedum
   roof, stone chimney smoking, shuttered window with flower box,
   root-woven door hinge, a door-side Aether-Conduit post (short
   bollard, lit teal) serving as the house terminal and address
   stone.

3. HALL (machine-leech): a two-story home built against the flank
   of a half-buried machine hull like the inn's grammar -- timber
   rooms clinging to overgrown alloy, a stable bay beneath, a
   small bell tower with a gold finial, laundry line, herb racks.
   The plot is fenced with cable-and-stake.

Labels: "SYNMERGIA: HOMESTEADS", "CLAIM", "COTTAGE", "HALL" only.
No other text.
```

---

## 2. The furniture kit (placeables)

**Prompt:**

```
[STYLE LOCK -- expanded]

Placeable-furniture sheet titled "SYNMERGIA: HEARTH KIT", eight
items in two rows of four on a white-grey background, same scale,
each item self-contained with a soft ground shadow: a stone
fireplace (lit warm, chimney smoke), a wooden chair with a root-
woven back, a plank bed with a rolled blanket, a timber workbench
with a small lit teal Conduit panel, a bookshelf of mixed salvage
shelves, a potted megaseed sprout in a gear-cog planter, a coat
rack trained from a polite root, a lantern post with an amber
glass lamp.

Labels: "SYNMERGIA: HEARTH KIT" only. No other text.
```

---

## 3. Hero shot: the claim (capstone)

**Prompt:**

```
[STYLE LOCK -- expanded]

Single cinematic key art, 16:9, dawn: an explorer kneels at a fresh
CLAIM tent on an empty grass plot, pressing their glowing tablet to
the doorpost wake-clasp -- a thin teal ring of light spreads along
the ground from the post, tracing the plot boundary like drawn
chalk. Everything else is quiet grey-green meadow with one distant
waypoint stone. The moment ownership begins; the world records it.
Left third open for UI.

Labels: "CLAIMED" only. No other text.
```

---

## Rendering checklist (for after generation)

- [ ] Warm windows in all three tiers; teal only at clasp/post/glyph
- [ ] No violet or magenta on any structure or furniture
- [ ] All three tiers readable as the SAME plot at different wealth
- [ ] Furniture kit survives at icon scale (squint test)
- [ ] Drop in Drive, attach favorites for critique
