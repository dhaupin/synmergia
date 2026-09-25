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

1. **Characters** -- species/class armor + weapon sheets (highest value).
2. **Hostile agent variants** -- combat-ready fauna.
3. **Bosses** -- at minimum the Forest Void Lord counterpart.
4. **Interiors + UI mockups** -- Echo Plaza inn, academy, inventory
   icons, HUD skin.
5. **Zone establishing shots** matching authored zones
   (zone_village, zone_capital, Gloomwood Meadow, dark_highlands...).

## 7. Prompt pipeline

Prompt briefs are staged in `labs/prompts/` for the human to run
through the image generator (Gemini). Naming:
`gemini_<subject>.md`. Each brief carries the style-lock block so
renders come back on-model. Finished art gets critiqued against this
bible, then either iteration or canonization (a place in the docs +
data files).
