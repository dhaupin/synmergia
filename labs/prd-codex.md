# Synmergia — The Codex: Full Data Viewer & Community Balance PRD

> **Status:** ACTIVE — the generic viewer ships; the community/balance surface is DESIGN.
> Status checked 2026-11-17.
> **Target Engine:** Godot 4.7.2
> **Author:** Web Architecture Team
> **Purpose:** Specify the public Codex as an unfiltered, machine-honest view of every
> `.tres` file the game ships, and the community-balance loop it exists to serve.

---

## 1. Thesis

Synmergia is open source. Every `.tres` file in `game/data/` is shipped content, and
players are entitled to see all of it — not a curated subset we decided was
presentable.

There is a second, harder reason. **We cannot balance this game as efficiently as the
players can.** A community of thousands running the numbers on `combat_balance.tres`
will find the degenerate build, the runaway curve, the stat that never pays off —
faster than any internal playtest. But only if the numbers are *visible*. The Codex
exists to hand players the evidence: the exact constant, the exact file, the exact
line. That turns "this feels off" into a legitimate, reproducible balance issue.

**The Codex is not a marketing page. It is the data layer of an open-source game, made
public.** Two laws follow:

1. **Nothing skipped.** Every `.tres` under `game/data/` appears. No category
   allowlist, no curated field list, no "we'll add that later."
2. **No hand-copied truth.** Every label, enum rung and count is derived from the
   source at build time. A value that is retyped in TypeScript is a value that will
   one day be wrong.

---

## 2. What Shipped (2026-11-17)

### 2.1 Producer — `scripts/sync_godot_data.ts`

- **Category discovery is a filesystem walk.** Every directory under `game/data/`
  holding at least one `.tres` becomes a payload key. Previously a hardcoded array of
  37 names silently excluded 19 populated directories (119 files): `balance`,
  `calibration`, `spawn_tables`, `hitbox_profiles`, `movement_profiles`,
  `npc_offerings`, `roots`, `targets`, `landmarks`, and more. Adding a directory now
  requires no code change.
- **`GodotDataPayload` is an open index signature**, so the type cannot reintroduce a
  field allowlist.
- **Keys are collision-proof.** Id-less resources key by their path within the
  category (`roots/world/environment`), and a duplicate key can never overwrite a
  sibling. Four `roots/*/environment.tres` files previously collapsed to one.
- **Canonical enum vocabulary** is read from `game/core/schemas/*.gd` (`enum` blocks +
  `@export var f: EnumType`) and emitted as `payload.vocab`. Ambiguous field names
  (`kind`, `category`, `source`) resolve per-class, never globally.

### 2.2 Consumer — `src/lib/codex.ts`, `src/pages/CodexPage.tsx`

- One entry per source file, every authored field, engine enum labels for enum-typed
  values, arrays/dicts as collapsible lists/maps, colours as swatches.
- Entry ids are namespaced by category (`balance:combat_balance`), so the all-category
  list has no React-key or selection collisions.

### 2.3 Guard — `scripts/verify_codex.mjs`

Gated into `npm run build`. Eleven checks, including the load-bearing one:

- **`nothing skipped: every game/data/**/*.tres is in the payload`** — walks the tree
  and asserts each file reached the payload. Verified to fail on the exact bug class
  it guards (drop `balance` → 10 missing, red).
- Enum fidelity: `ResourceType` is the engine ladder; every class `resource_type` is in
  range; `focal_stat_1/2` present.

### 2.4 Current coverage

**55 categories, 1097 entries** — the full tree. `combat_balance.tres` alone exposes
36 tuning constants (hit/dodge/parry/block curves, armour curve, level-power band,
regen rates).

---

## 3. Balance Surface (the point of the exercise)

The balance files are the highest-value Codex content and should be the most
legible. Today they render as a flat field list, which is honest but not yet
*usable* for a balance argument.

**Design goals:**

- **Grouped, not flat.** `combat_balance.tres` should read as
  *Avoidance* (hit/dodge/parry/block), *Mitigation* (armour curve, cap),
  *Scaling* (level power), *Regeneration* — not 36 unordered rows.
- **Stable deep links.** Every field needs a permalink
  (`/codex/balance/combat_balance#dodge_cap`) so a player can cite one constant in an
  issue. This is the whole evidence chain.
- **Diff view.** "What changed between two game versions" for a given file. Balance
  complaints are almost always about a *change*; surfacing the diff is the strongest
  possible evidence.
- **Raw + rendered.** Show the number as authored, with any derived display
  (percentage, per-level) alongside — never instead.

---

## 4. Community Loop (DESIGN)

The Codex is the input to a feedback pipeline. Target shape:

1. **See** — a player finds a constant in the Codex.
2. **Cite** — a stable permalink, with file path and value, copied into an issue.
3. **Propose** — a structured balance-issue template pre-filled with the file, field
   and current value, plus the player's proposed value and rationale.
4. **Discuss** — balance issues are first-class, labelled, and public.
5. **Ship** — an accepted change edits the `.tres`; the next sync and Codex deploy
   close the loop automatically, and the diff view shows what moved.

**Principle:** the pipeline must never require a maintainer to transcribe a number by
hand. Every step reads the same `.tres` source of truth.

---

## 5. Next Steps

### P0 — correctness (parked, must land before promotion)
- [ ] **Audit `roots/` id semantics.** All 17 files are id-less; the path-based key is
      a display workaround. Decide whether roots should carry authored ids, or whether
      the path key is canonical. Affects any future root editor.
- [ ] **Re-check the alias injection.** `sync_godot_data.ts` injects bare
      base-archetype class aliases (`warrior` ← `human_warrior`). This inflates
      `counts.classes` to 39 from 21 authored files (18 playable + 3 GM), and
      read that number as "playable classes". Either mark the alias explicitly
      (`_aliasOf`) or exclude it from counts. Decide with the gamestruct lane.
- [ ] **Verify the 8 cross-category id collisions are genuinely distinct content**,
      not a data-authoring error (e.g. `first_blood`, `explorer`, `trader` appearing in
      two categories).

### P1 — balance usability
- [ ] Field grouping for balance schemas (Section 3).
- [ ] Stable per-field permalinks.
- [ ] Codex-aware balance-issue template.

### P2 — community surface
- [ ] Version-to-version diff view.
- [ ] "Raw" export (`/codex.json`) so the community can analyse the tree offline.
- [ ] Cross-link Codex entries to the systems that consume them (`labs/prd-combat.md`,
      `labs/prd-economy.md`).

### Housekeeping
- [ ] Update `labs/README.md` index to list this doc.
- [ ] `src/components/admin/AdminDashboardView.tsx` still reads `godotData.classes` and
      `godotData.weapons` by name; confirm it benefits from (or is unaffected by) the
      open payload.

---

## 6. Change Log

| Date | Author | Summary |
|------|--------|---------|
| 2026-11-17 | Web Architecture Team | Initial creation. Codex became a generic `.tres` viewer; category discovery moved to a filesystem walk (37 → 55 categories, 978 → 1097 entries); canonical enum vocabulary read from `.gd` schemas; `verify_codex.mjs` guard added to the build. Balance/community surface specified as DESIGN. |
