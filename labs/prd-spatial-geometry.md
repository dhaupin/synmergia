# PRD: Spatial Geometry Fragmenter (Vant → Synmergia)

> **For:** geometry layer implementation
> **Phase:** 4 (per `world-building-arch.md` §11.4, §14, §16)
> **Depends on:** `prd-geometry.md` (data fragmenter), `game/core/frame/math/nsc9.gd`, `game/core/frame/math/icosahedral.gd`
> **Unblocks:** LOD scoping, spatial memory compression, deterministic client/server subdivision

## 1. Introduction/Overview

The spatial geometry fragmenter decomposes discrete spatial cells (icosahedral faces, NSC-9 cells, or generic quantized volumes) into deterministic sub-fragments. Unlike the Vant data fragmenter (`fragmenter.gd`) which shards bytes, this module shards **space** itself.

**Why this exists:** Per architecture review, a clean geometry fragmenter is the engine behind:
- Deterministic sub-cell addressing (client/server subdivide without exchanging mesh data)
- Spatial memory compression (content-addressable bounding volumes, prune empty regions)
- Seamless multi-resolution scoping (LOD: deep fine-grained fragments for combat, unfragmented parents for world-level weather/faction tracking)

**Design principles:**
- **Pure functions:** no state, no side-effects
- **Integer/quantized math only:** no floating-point seam cracks
- **Fixed-width 64-bit address encoding:** no hash collisions
- **MAX_DEPTH guard:** prevents fragment explosion (tree depth runaway)
- **Deterministic:** same input → same output, always

**Spec refs:**
- [`world-building-arch.md`](./world-building-arch.md) §16 (Geometric addressing)
- [`world-building-arch.md`](./world-building-arch.md) §13 Component map
- [`prd-geometry.md`](./prd-geometry.md) (data fragmenter baseline)

## 2. Goals

- ONE `spatial_fragmenter.gd` in `game/core/frame/geometry/` — pure functions, no state
- 64-bit address encoding: depth + spatial offsets + face/region type
- Deterministic octree-style subdivision (8 children per cell)
- Integer-only bounding boxes (quantized min/max)
- Ancestor/parent lineage checks
- Common ancestor computation (spatial compression)
- MAX_DEPTH limit to prevent fragment explosion
- Co-located test file `test_spatial_fragmenter.gd`

## 3. User Stories

### US-001: Deterministic sub-cell addressing

**Description:** As a developer, I need a `subdivide(address: int, depth: int = 1) -> Array[int]` function that deterministically splits a cell into 8 child cells, so client and server can recursively subdivide spatial state on the fly without exchanging mesh data.

**Acceptance Criteria:**
- [ ] Function exists in `game/core/frame/geometry/spatial_fragmenter.gd`
- [ ] Returns exactly 8 children per subdivision step (unless MAX_DEPTH reached)
- [ ] Children inherit parent face/region type
- [ ] Same input → same output, always
- [ ] Depth increments by requested amount (capped at MAX_DEPTH)

### US-002: Integer-only bounding volumes

**Description:** As a developer, I need `get_bounding_box(address: int) -> Dictionary` to return quantized integer min/max bounds, so spatial regions can be content-addressed without floating-point seam cracks.

**Acceptance Criteria:**
- [ ] Returns Dictionary with `min_x`, `min_y`, `min_z`, `max_x`, `max_y`, `max_z`, `depth`, `face`
- [ ] All values are integers (no floats)
- [ ] Bounding box volume decreases monotonically with depth
- [ ] Parent and child boxes are consistent (no gaps/overlaps beyond quantization)

### US-003: Face/region isolation

**Description:** As a developer, I need `get_face(address: int) -> int` and face-aware subdivision, so icosahedral faces (0-19) and NSC-9 prefix (9) never collide or cross-contaminate.

**Acceptance Criteria:**
- [ ] Face is encoded in top 8 bits of the 64-bit address
- [ ] Subdivision preserves face
- [ ] Ancestor checks reject cross-face lineage
- [ ] Common ancestor returns 0 for cross-face inputs

### US-004: Parent and ancestor lineage

**Description:** As a developer, I need `get_parent(address: int) -> int` and `is_ancestor(ancestor: int, descendant: int) -> bool` for LOD scoping and spatial queries.

**Acceptance Criteria:**
- [ ] `get_parent` returns the immediate coarser cell
- [ ] `is_ancestor` returns true for self and all coarser cells on the same lineage
- [ ] `is_ancestor` returns false for cross-face or non-lineage pairs

### US-005: Common ancestor (spatial compression)

**Description:** As a developer, I need `find_common_ancestor(addresses: Array[int]) -> int` to collapse multiple fragments into their coarsest shared cell, enabling spatial memory compression.

**Acceptance Criteria:**
- [ ] Empty array → 0
- [ ] Single address → the address itself
- [ ] Multiple same-face addresses → coarsest shared ancestor
- [ ] Cross-face addresses → 0

### US-006: Collision-free address keys

**Description:** As a developer, I need `generate_key(address: int) -> String` with fixed-width formatting, so cell 1 sub-fragment 12 never collides with cell 11 sub-fragment 2.

**Acceptance Criteria:**
- [ ] Format: `%04x-%04x-%04x-d%d-f%d` (x, y, z, depth, face)
- [ ] Fixed-width hex padding on x/y/z
- [ ] Distinct addresses → distinct keys

### US-007: Depth limit (fragment explosion guard)

**Description:** As a developer, I need `MAX_DEPTH = 24` to cap subdivision depth, so high entity density cannot cause infinite recursion or tick latency blowups.

**Acceptance Criteria:**
- [ ] `subdivide` returns the input address unchanged when at MAX_DEPTH
- [ ] `get_depth` never exceeds MAX_DEPTH

### US-008: Test coverage

**Description:** As a developer, I need a co-located test file `test_spatial_fragmenter.gd` covering all functions and edge cases.

**Acceptance Criteria:**
- [ ] Test file at `game/core/frame/geometry/test_spatial_fragmenter.gd`
- [ ] Tests: subdivision count, parent linkage, ancestor checks, depth tracking, MAX_DEPTH, face isolation, bounding box, common ancestor, address key uniqueness, round-trip consistency, determinism
- [ ] Runs with `godot --headless --path . --script res://core/frame/geometry/test_spatial_fragmenter.gd`
- [ ] Exit code 0 on pass, non-zero on fail

## 4. Functional Requirements

- **FR-1:** Single file `game/core/frame/geometry/spatial_fragmenter.gd` with `SpatialFragmenter` class
- **FR-2:** Constant `MAX_DEPTH = 24`
- **FR-3:** 64-bit address encoding: x (16 bits), y (16 bits), z (16 bits), depth (8 bits), face (8 bits)
- **FR-4:** `make_address(x: int, y: int, z: int, depth: int, face: int = 0) -> int`
- **FR-5:** `get_x`, `get_y`, `get_z`, `get_depth`, `get_face` accessors
- **FR-6:** `subdivide(address: int, depth: int = 1) -> Array[int]`
- **FR-7:** `get_parent(address: int) -> int`
- **FR-8:** `is_ancestor(ancestor: int, descendant: int) -> bool`
- **FR-9:** `get_bounding_box(address: int) -> Dictionary`
- **FR-10:** `find_common_ancestor(addresses: Array[int]) -> int`
- **FR-11:** `generate_key(address: int) -> String`
- **FR-12:** NO autoload, NO GameManager dependency
- **FR-13:** Tests in co-located `test_spatial_fragmenter.gd`

## 5. Non-Goals (Out of Scope)

- NO floating-point math (intentionally excluded to avoid seam cracks)
- NO mesh generation (geometry is address-level; mesh data is a separate layer)
- NO persistence (pure functions; storage is via T3 / adapter layer)
- NO provider coupling (scatter/retrieve are game-layer concerns)
- NO dynamic depth adjustment beyond MAX_DEPTH

## 6. Design Considerations

### Why 64-bit addresses?
- Bitwise operations are orders of magnitude faster than string concatenation during 20Hz frame ticks
- Fixed-width fields eliminate hash collisions (e.g., `1-12` vs `11-2`)
- Face + depth + spatial offsets fit cleanly in 64 bits

### Why integer/quantized math?
- Floating-point rounding differs across hardware (float32/float64, GPU/CPU)
- Integer coordinates guarantee identical boundaries on client and server
- No seam cracks at cell boundaries

### Why octree-style subdivision?
- 8 children per step is a clean power-of-two split
- Bounding boxes are trivial to compute from quantized offsets
- Depth maps directly to LOD level

### Why MAX_DEPTH = 24?
- 2^24 ≈ 16.7M subdivisions per axis — far beyond any practical spatial need
- Prevents infinite recursion from pathological input
- Keeps tick latency bounded

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `int`, `Array`, `Dictionary`, bitwise ops)
- **No external dependencies** beyond Godot stdlib
- **Pure functions:** no state, no side-effects
- **Tests:** co-located `test_spatial_fragmenter.gd`

## 8. Success Metrics

- All 8 user stories have passing tests (≥ 40 assertions)
- Deterministic subdivision verified across repeated runs
- No floating-point values in bounding boxes
- No address key collisions for distinct addresses
- MAX_DEPTH prevents fragment explosion
- `game/core/frame/geometry/` directory contains `spatial_fragmenter.gd` + `test_spatial_fragmenter.gd`
- `labs/world-building-arch.md` §13 component map updated: "Spatial geometry fragmenter" → DONE
- Single commit, conventional message format

## 9. Open Questions

1. **Face encoding:** NSC-9 prefix (9) vs icosahedron faces (0-19). Should face be a generic region type (8-bit) or a typed enum? Current design: generic 8-bit region type, caller interprets.
2. **NSC-9 integration:** `Nsc9.encode_int()` returns a 14-digit string. Should we add a helper to convert NSC-9 → `SpatialFragmenter` address? Current design: caller extracts x/y/z/depth/face from NSC-9 fields.
3. **Icosahedral integration:** icosahedral faces are triangular, not cubic. Should subdivision be barycentric (4 children) or octree-style (8 children)? Current design: octree-style for clean bounding boxes; barycentric is a future extension.

## 10. Definition of Done

- [ ] `game/core/frame/geometry/spatial_fragmenter.gd` created with all functions
- [ ] `game/core/frame/geometry/test_spatial_fragmenter.gd` created and passing
- [ ] `labs/world-building-arch.md` §13 component map: "Spatial geometry fragmenter" row status → DONE
- [ ] File headers include Vant lineage credit
- [ ] Smoke test: subdivide → parent → ancestor → bounding box → key
- [ ] One commit to main
