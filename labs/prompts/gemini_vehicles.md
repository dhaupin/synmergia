# Vehicles (Gemini brief pack)

> **Goal:** multi-passenger transport platforms, in case vehicles
> ship alongside mounts. Design split: **mounts are single-rider
> fauna/constructs; vehicles are multi-passenger platforms and cargo
> haulers.** There is no vehicle data in `game/data/` yet -- this
> pack is the design seed, hooked to existing canon: the conduit
> pipes that lace every ruin (WaypointService's future network),
> the floating islets and their dormant orb machines (Dark
> Highlands, duel key art), and the station law (teal idle / gold
> active, sec. 8.10-8.11 era canon).
>
> Companion pack: `gemini_mounts.md` (same wake-verb, smaller scale).

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
aesthetic. Clean white-grey presentation background, 16:9 sheet with
a thin margin, hand-lettered style labels under each figure (short
labels only). Render ONLY the exact label words listed at the end --
no filenames, no other text.
```

**Vehicle law for this pack (every prompt):** vehicles are the
world's own dormant transports, WOKEN by a tablet -- never built,
fueled, or manufactured. No engines, no smokestacks, no fuel tanks,
no wheels, no enclosed cabins or cockpit glass -- open platforms
with root-wrapped grips and a **tablet socket** as the helm (the
pilot's tablet docks into it). Propulsion is dormant tech: conduit
induction, orb-lift, root-muscle. Color: teal = dormant/waking,
gold = active/underway (the station law). ZERO magenta; violet
forbidden on vehicles; moss and hanging gardens always welcome.

---

## 1. Transport platforms (one sheet, three vehicles)

**Prompt:**

```
[STYLE LOCK -- expanded]

Vehicle sheet titled "SYNMERGIA: WAKENED CONVEYANCE", three side-
view platforms in a row, same scale, each with open seating for
several riders and a tablet-socket helm:

1. CONDUIT GLIDER: a low four-seat draisine that rides dormant
   conduit lines like a rail -- two smooth skid pads straddle the
   pipe, a leaf-shaped ceramic hull with moss along the spine,
   teal induction veins lighting along its underside, root-woven
   bench seats facing outward, wind-catch prow of pale bone.

2. ISLET LIFTER: a wide stone-and-alloy platform ringed by four
   dormant orb machines (the same orbs that hold the floating
   islets aloft) on curved arms; waking, the orbs glow teal and
   the platform hovers a hand-span up. Open deck with cargo
   rings, banner pole, and a center helm pedestal with tablet
   socket.

3. CARAVAN CRAWLER: a broad cargo hauler on six root-muscled
   legs -- machine hull wrapped in living root and moss, a flat
   market deck with tie-downs and a rolled awning, slow patient
   teal seams. The guild-move and market-train workhorse.

Labels: "SYNMERGIA: WAKENED CONVEYANCE", "CONDUIT GLIDER", "ISLET
LIFTER", "CARAVAN CRAWLER" only. No other text.
```

---

## 2. Wake-state pair (dock vs underway)

**Prompt:**

```
[STYLE LOCK -- expanded]

Two-state study, one CONDUIT GLIDER shown twice side by side, same
scale and angle: LEFT dormant at a waypoint dock -- dark hull,
veins unlit, moss thick, a traveler's tablet resting in the helm
socket; RIGHT underway -- the same glider skimmed up onto a lit
conduit line, underside veins switched from teal to GOLD (active),
moss streaming back, two riders gripping the root rails, motion
lines minimal, mist parting. The dock: a short platform with a
waypoint stone and a ticket glyph post.

Labels: "DORMANT", "UNDERWAY" only. No other text.
```

---

## 3. Hero shot: the departure (capstone)

**Prompt:**

```
[STYLE LOCK -- expanded]

Single cinematic key art, 16:9, dawn in the Dark Highlands: an
ISLET LIFTER carrying a full party -- Human, Akkan, Synthetic --
rising past a waterfall that pours off a floating islet, its four
orb machines glowing GOLD, banners and cargo rings swaying. Below,
the monolith field and its burning ember sigils; above, the bruised
sky breaking light. Quiet grandeur, travel as ceremony. Left third
open for UI.

Labels: "THE DEPARTURE" only. No other text.
```

---

## Rendering checklist (for after generation)

- [ ] ZERO magenta; violet forbidden; no engines/wheels/cabins
- [ ] Tablet socket visible as the helm on all three
- [ ] Gold = underway, teal = dormant (station law continuity)
- [ ] Silhouettes distinct at squint range; platforms read as
      multi-rider, not solo mounts
- [ ] Same ink weight as the mounts sheet
- [ ] Drop in Drive, attach favorites for critique

---

## The two movers (canon, 2026-11-05, from the monetization trade)

> **Canon home: `labs/prd-ancient-movers.md`** -- this seed is the inspiration
> shelf; the lab PRD carries the law.

Standing law, recorded wherever vehicles are recorded. PERSONAL MOVERS are
player-owned: a platform woken by YOUR tablet, a mount, a glider, a breather
helmet. They wear honestly, repair FREE at stations, take Mender's Kits into
the field and modifiers at the bench. ANCIENT MOVERS are the server-unlocked
ancients: the ferries on their honesty law, the dormant ruin movers, the
orb-borne islet lifters already loose in the world before anyone claims them.
An ANCIENT mover belongs to no player and never prices a personal SKU — its
bill is a CIVIC bill (settlement deeds, warden take, Concord sinks). No engine
exists to fuel in either lane: a MEND is binding work, a MODIFIER is verse
work; see prd-monetization.md sec 29 for the trade's prices and laws.

## The Mystery Gate (the ancients' wake-keys, canon 2026-11-05)

> **Canon home: `labs/prd-ancient-movers.md`** (secs 5-8: lifecycle, wake-keys,
> sealed keys, the known ancients table). This seed keeps its briefs and its
> wake-verbs as inspiration only.

The gap the owner flagged: the two-movers canon said the ancients are DORMANT,
but no PRD ever wrote what wakes them. THE MYSTERY GATE closes the pipe.
EVERY server-unlocked thing — ancient movers, sealed gates, hidden abilities,
dormant world physics, anything deep — holds its wake-key behind the world,
never before the store.

THE FIVE WAKE-KEYS (each an open lane; an ancient may hold one or many):
1. THE PUZZLE — a server puzzle wakes it: a riddle spread across the world's
   own texts, monuments and seasons, solved by players, not by walkthroughs
   the servers ever published.
2. THE TRAM EFFORT — the effortful road wakes it: trips walked, hauls made,
   crowds carried — a route's honest use is itself the key, so the road
   wakes what the road serves.
3. THE OBSERVATION — the patient watcher wakes it: things noticed where
   nobody looks (a moon's shadow at a bearing, a light under an islet's
   root), reporting and reading rewarded.
4. THE INTERACTION — the ritual hand wakes it: gestures, offerings, tablet
   statutes touched in the right order at the right ground.
5. THE PURE LUCK — nobody wakes it; it wakes: a rare spawn or a season
   rolls its own chance, and who was standing there was the key.

THE SEALED KEYS: some wake conditions are written ONLY server-side — absent
from design docs by design, and sometimes beyond any one dev's knowledge by
design (the owner's line: "some even the devs don't know"). The team
discovers alongside the players; docs may speak of a SOUL in terms of its
family and its laws, never of its sealed keys.

THE LAW: mystery is the momentum (the owner's confession: "our sense of
mystery is the momentum, everywhere"). NOTHING purchasable opens a wake-key:
not the kits, not the modifiers, not the seats, not the ankh's blessing —
the Concord's Table's twenty rows price what exists and none wakes the
unwoken. Crosslinks: prd-ocean-depths.md's ferry law (the schedule is the
ONE wake-key carved in the open) and prd-monetization.md sec 28/29.
