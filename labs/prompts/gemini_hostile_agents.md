# Hostile Agent Fauna (Gemini brief pack)

> **Goal:** the combat-ready counterpart to the neutral fauna spotlight.
> The current set's agents (Data-Owl, Spore-Spider, Root-Crab,
> Lichen-Lizard) read calm -- we need the corrupted/hostile variants
> players actually fight, with a consistent "this one is hostile" key.

---

## 0. STYLE LOCK (paste the full paragraph into the prompt -- never a placeholder token)

```
Stylized cyber-organic fantasy concept art, inked outlines with
cel-shaded flats and painted texture. A world of ancient dormant
symbiotic technology overgrown by nature: geometric circuit forms
wrapped in roots, moss, and mycelium. Desaturated grey-green base
palette (#c0c0c0 stone, #404040 shadow, #202020 dark) with three
semantic accent colors ONLY: pale teal/cyan (#80c0c0) for dormant or
waking technology, warm gold (#c0a060) for active converged
technology, violet (#8060c0) exclusively for mycelium and arcane
magic. No photorealism, no low-poly look, no neon cyberpunkaesthetic. Clean white-grey presentation background, 16:9 sheet with
a thin margin, hand-lettered style labels under each figure (short
labels only, no paragraphs of text).

IMPORTANT TEXT RULE: render ONLY the exact species/variant names listed
at the end of the prompt. Do NOT render filenames, hex codes, or any
other text -- readable wrong words are drift. Decorative glyph
scribbles are fine.
```

---

## 1. Hostile variants sheet

**The hostility key (make it loud and consistent):** hostile agents
have **magenta-thread eyes** (a hot magenta-pink, deliberately OUTSIDE
the three accent domains -- it reads as "wrong"), **cracked or pried
shell plating**, and **leaking spore-dust or frayed cables**. Where the
neutral variant glows teal, the hostile one flickers unstable.

**Prompt:**

```
[STYLE LOCK]

Bestiary sheet titled "SYNMERGIA: CORRUPTED AGENTS", two rows of two,
each creature shown as a paired study: the neutral form small on the
left, the hostile variant large on the right, connected by a thin
arrow. All hostile variants share: hot magenta-pink glowing eyes,
cracked or pried-open shell plating, frayed cables or leaking
spore-dust, aggressive silhouette.

Row 1:
- SPORE-SPIDER -> FERAL SPORE-SPIDER: the calm glass-backed spider
  becomes hunched and bristling, its crystal sac fractured and
  venting violet spore-dust, legs ending in torn metal hooks,
  magenta eyes. Mid-lunge pose.
- DATA-OWL -> SHRIKE-OWL: the calm perched owl becomes a sleek
  strike-frame, sensor crest split into twin ears laid flat, talon
  cables barbed, magenta eye-slit. Wings spread in a stoop.

Row 2:
- ROOT-CRAB -> RUST-ROOT-CRAB: the mossy grazer becomes a siege
  shell, one claw overgrown into a split boulder-mace, rust flaking
  off torn plating, roots wound tight like tendon. Scuttling charge.
- LICHEN-LIZARD -> BLIGHT-LIZARD: the sleepy lizard becomes taut and
  long-limbed, skin lichen turned from pale olive to bruised violet
  patches, tail splitting into cable-whip frays, magenta eyes.

Labels: species names only, correctly spelled. Keep the ink weight and
proportions consistent with the "FAUNA SPOTLIGHT" sheets (geometric
agents, animal silhouette first, tech second).
```

> **Status:** rendered + canonized 2026-09-25. The magenta hostility
> key survived generation (pixel-audited across the drop: magenta <1%
> of frame area, only on corrupted agents -- labs/art-direction.md
> sec. 8.1). The Shrike-Owl battle study is the first action render
> of a hostile agent; its cracked clock-face core is canon.

---

## 2. Hostile agents in the field (action scenes)

Single-creature action scenes beat sheets for hero moments. Battle
study example (Shrike-Owl, rendered 2026-09-25): one hostile agent
mid-fight against an explorer party, full environment -- the world
reads better in action than in isolation.

**Prompt (template -- swap species and terrain):**

```
[STYLE LOCK]

Action battle study, 16:9: a SHRIKE-OWL (corrupted Data-Owl) diving
at an Akkan warrior on a broken stone bridge over a crystal-ringed
ruin canyon. The owl: stone-grey feather-plate, violet mycelium
swirls in the wing membranes, a cracked clock-face core in its chest
venting black spore-smoke, cables whipping from its wing joints, hot
magenta eyes. The warrior: angular bronze war-plate with gold trim,
grey-violet skin, ember eyes, braced behind an inscribed slab-blade.
Spore-Spiders (small, violet-capped, magenta-eyed) scatter below.
Teal crystal clusters frame the scene; sky pale grey-green, distant
Dormant spire towers. No text, no labels.
```

---

## Rendering checklist

- [ ] Magenta hostility key present on ALL four variants, nowhere on
      neutral forms
- [ ] Violet reserved for spore/mycelium leakage only (eyes are
      magenta-pink, not violet -- check this, generators love to merge them)
- [ ] Neutral->hostile pairs clearly the same creature
- [ ] Silhouettes still animal-first
