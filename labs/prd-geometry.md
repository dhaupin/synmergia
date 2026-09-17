# PRD: Geometry Layer  -  Vant Fragmenter Port + Spatial Fragmenter Integration

> **For:** sub-agent implementation
> **Phase:** 4 (per `world-building-arch.md` sec. 11.4, sec. 14)
> **Depends on:** `prd-t3-substrate.md` (for content-hash keys), `prd-seed-schema.md` (for sequence derivation), `world-building-arch.md` sec. 16 (Vant geometric addressing)
> **Unblocks:** Edge shards (sec. 11.4), spatial sub-cell addressing, shard partitioning via lattice keys

## 1. Introduction/Overview

The geometry layer has **two distinct ported modules** from Vant:

### 1A. Aperiodic Fragmenter (stateless data sharding)
- `game/core/frame/geometry/fragmenter.gd`  -  Knuth multiplicative hash, `derive_lattice_keys`, `fragment`, `weld`
- Stateless: no central manifest, no lookup tables
- Pure data sharding across N lattice positions

### 1B. Spatial Geometry Fragmenter (deterministic sub-cell addressing)
- `game/core/frame/geometry/spatial_fragmenter.gd`  -  64-bit address encoding, octree subdivision, bounding boxes, lineage
- Deterministic: same input  ->  same output, always
- Pure spatial addressing (x/y/z/depth/face), no data sharding

**Why both exist:** Per architecture review, the frame needs both:
- **Data fragmentation** for distributed storage (fragmenter.js  ->  fragmenter.gd)
- **Spatial subdivision** for client/server sub-cell addressing without mesh data exchange (spatial_fragmenter.gd  -  new)

**Design principles (both):**
- Pure functions: no state, no side-effects
- Integer/quantized math only
- Deterministic: same input  ->  same output, always
- Fixed-width encoding: no hash collisions

## 2. Goals

### 2A. Aperiodic Fragmenter (existing goals, unchanged)
- ONE `fragmenter.gd` in `game/core/frame/geometry/`  -  pure functions, no state
- Implement Vant's `derive_lattice_keys`, `fragment`, `weld` (core API)
- Knuth multiplicative hash with `LATTICE_MULTIPLIER = floor(phi * 2^32) = 2654435769`
- Stateless: no lookup tables, no central manifest, no provider coupling
- Co-located test file `test_fragmenter.gd` covering all functions

### 2B. Spatial Geometry Fragmenter (new, added 2026-09-17)
- ONE `spatial_fragmenter.gd` in `game/core/frame/geometry/`  -  pure functions, no state
- 64-bit address encoding: x (16-bit), y (16-bit), z (16-bit), depth (8-bit), face (8-bit)
- Deterministic octree-style subdivision (8 children per cell)
- Integer-only bounding boxes (quantized min/max)
- Ancestor/parent lineage checks
- Common ancestor computation (spatial compression)
- MAX_DEPTH = 24 guard prevents fragment explosion
- Co-located test file `test_spatial_fragmenter.gd`

## 3. User Stories

### US-001: Lattice key derivation (fragmenter)
**Description:** As a developer, I need `derive_lattice_keys(sequence: int, num_fragments: int = 5) -> Array[String]` that deterministically derives N aperiodic lattice keys from a single sequence integer.

**Acceptance Criteria:**
- [ ] Function exists in `game/core/frame/geometry/fragmenter.gd`
- [ ] Uses `LATTICE_MULTIPLIER = 2654435769` (Knuth's `floor(phi * 2^32)`)
- [ ] Returns `Array[String]` of length `num_fragments` (base-36 encoded)
- [ ] Deterministic: same sequence + same num_fragments  ->  same keys
- [ ] Progressive keystream: key[i] derived from `(baseHash + i) * MULTIPLIER`

### US-002: Data fragmentation (fragmenter)
**Description:** As a developer, I need `fragment(data: Variant, num_fragments: int = 5) -> Array[Dictionary]` that splits arbitrary data into N fragments with XOR spreading.

**Acceptance Criteria:**
- [ ] Function exists in `fragmenter.gd`
- [ ] Accepts `Variant`  -  JSON stringifies non-strings
- [ ] Returns `Array[Dictionary]` with keys: `shard` (int), `data` (base64 String), `size` (int), `checksum` (int)
- [ ] XOR spreading: each byte XOR'd with `((shard + 1) * 137 >> 5)`
- [ ] Checksum: `sum(byte * (i + 1)) % 65536` per fragment
- [ ] Round-trip: fragment + weld recovers original data exactly

### US-003: Fragment welding (fragmenter)
**Description:** As a developer, I need `weld(fragments: Array) -> String` that reconstructs original data from fragments.

**Acceptance Criteria:**
- [ ] Function exists in `fragmenter.gd`
- [ ] Accepts fragments as `Array[Dictionary]` (with `shard`, `data`) OR `Array[String]` (base64 only)
- [ ] Sorts by `shard` before decoding
- [ ] Reverses XOR spreading: `decoded[i] ^ ((shard + 1) * 137 >> 5)`
- [ ] Concatenates and returns UTF-8 string

### US-004: Spatial sub-cell addressing (spatial_fragmenter)
**Description:** As a developer, I need a `subdivide(address: int, depth: int = 1) -> Array[int]` function that deterministically splits a cell into 8 child cells, so client and server can recursively subdivide spatial state on the fly without exchanging mesh data.

**Acceptance Criteria:**
- [ ] Function exists in `game/core/frame/geometry/spatial_fragmenter.gd`
- [ ] Returns exactly 8 children per subdivision step (unless MAX_DEPTH reached)
- [ ] Children inherit parent face/region type
- [ ] Same input  ->  same output, always
- [ ] Depth increments by requested amount (capped at MAX_DEPTH)

### US-005: Integer-only bounding volumes (spatial_fragmenter)
**Description:** As a developer, I need `get_bounding_box(address: int) -> Dictionary` to return quantized integer min/max bounds.

**Acceptance Criteria:**
- [ ] Returns Dictionary with `min_x`, `min_y`, `min_z`, `max_x`, `max_y`, `max_z`, `depth`, `face`
- [ ] All values are integers (no floats)
- [ ] Bounding box volume decreases monotonically with depth
- [ ] Parent and child boxes are consistent

### US-006: Face/region isolation (spatial_fragmenter)
**Description:** As a developer, I need `get_face(address: int) -> int` and face-aware subdivision, so NSC-9 prefixes and icosahedron faces never collide.

**Acceptance Criteria:**
- [ ] Face is encoded in top 8 bits of the 64-bit address
- [ ] Subdivision preserves face
- [ ] Ancestor checks reject cross-face lineage

### US-007: Parent and ancestor lineage (spatial_fragmenter)
**Description:** As a developer, I need `get_parent(address: int) -> int` and `is_ancestor(ancestor: int, descendant: int) -> bool` for LOD scoping.

**Acceptance Criteria:**
- [ ] `get_parent` returns the immediate coarser cell
- [ ] `is_ancestor` returns true for self and all coarser cells on the same lineage
- [ ] `is_ancestor` returns false for cross-face or non-lineage pairs

### US-008: Common ancestor computation (spatial_fragmenter)
**Description:** As a developer, I need `find_common_ancestor(addresses: Array[int]) -> int` to collapse multiple fragments into their coarsest shared cell.

**Acceptance Criteria:**
- [ ] Empty array  ->  0
- [ ] Single address  ->  the address itself
- [ ] Multiple same-face addresses  ->  coarsest shared ancestor
- [ ] Cross-face addresses  ->  0

### US-009: Collision-free address keys (spatial_fragmenter)
**Description:** As a developer, I need `generate_key(address: int) -> String` with fixed-width formatting.

**Acceptance Criteria:**
- [ ] Format: `%04x-%04x-%04x-d%d-f%d` (x, y, z, depth, face)
- [ ] Fixed-width hex padding on x/y/z
- [ ] Distinct addresses  ->  distinct keys

### US-010: Depth limit guard (spatial_fragmenter)
**Description:** As a developer, I need `MAX_DEPTH = 24` to cap subdivision depth.

**Acceptance Criteria:**
- [ ] `subdivide` returns the input address unchanged when at MAX_DEPTH
- [ ] `get_depth` never exceeds MAX_DEPTH

### US-011: Test coverage (spatial_fragmenter)
**Description:** As a developer, I need a co-located test file `test_spatial_fragmenter.gd` covering all functions and edge cases.

**Acceptance Criteria:**
- [ ] Test file at `game/core/frame/geometry/test_spatial_fragmenter.gd`
- [ ] Tests: subdivision count, parent linkage, ancestor checks, depth tracking, MAX_DEPTH, face isolation, bounding box, common ancestor, address key uniqueness, round-trip consistency, determinism
- [ ] Runs with `godot --headless --path . --script res://core/frame/geometry/test_spatial_fragmenter.gd`
- [ ] Exit code 0 on pass, non-zero on fail

## 4. Functional Requirements

### FR-1A: Aperiodic Fragmenter (existing)
- **FR-1:** Single file `game/core/frame/geometry/fragmenter.gd` with `Fragmenter` class
- **FR-2:** Constant `LATTICE_MULTIPLIER = 2654435769`
- **FR-3:** `derive_lattice_keys(sequence: int, num_fragments: int = 5) -> Array[String]`
- **FR-4:** `fragment(data: Variant, num_fragments: int = 5) -> Array[Dictionary]`
- **FR-5:** `weld(fragments: Array) -> String`
- **FR-6:** `class_name Fragmenter` permitted (frame primitive with instantiation; NOT an autoload) per AGENTS.md sec. Autoloads
- **FR-7:** NO external dependencies beyond Godot stdlib
- **FR-8:** Tests in co-located `test_fragmenter.gd`

### FR-1B: Spatial Geometry Fragmenter (new)
- **FR-9:** Single file `game/core/frame/geometry/spatial_fragmenter.gd` with `SpatialFragmenter` class
- **FR-10:** Constant `MAX_DEPTH = 24`
- **FR-11:** 64-bit address encoding: x (16 bits), y (16 bits), z (16 bits), depth (8 bits), face (8 bits)
- **FR-12:** `make_address(x: int, y: int, z: int, depth: int, face: int = 0) -> int`
- **FR-13:** `get_x`, `get_y`, `get_z`, `get_depth`, `get_face` accessors
- **FR-14:** `subdivide(address: int, depth: int = 1) -> Array[int]`
- **FR-15:** `get_parent(address: int) -> int`
- **FR-16:** `is_ancestor(ancestor: int, descendant: int) -> bool`
- **FR-17:** `get_bounding_box(address: int) -> Dictionary`
- **FR-18:** `find_common_ancestor(addresses: Array[int]) -> int`
- **FR-19:** `generate_key(address: int) -> String`
- **FR-20:** NO autoload, NO GameManager dependency
- **FR-21:** Tests in co-located `test_spatial_fragmenter.gd`

## 5. Non-Goals (Out of Scope)

### Fragmenter (unchanged)
- NO provider coupling in frame layer (scatter/retrieve/incinerate are game-layer; see US-101/102/103 in Phase 4)
- NO async/await (pure synchronous functions)
- NO encryption (XOR spreading is obfuscation, not crypto)
- NO manifest/index (stateless by design)
- NO icosahedral/Penrose/quasicrystal math (separate math primitives in `game/core/frame/math/`)

### Spatial Fragmenter (new)
- NO floating-point math (intentionally excluded to avoid seam cracks)
- NO mesh generation (geometry is address-level; mesh data is separate layer)
- NO persistence (pure functions; storage is via T3 / adapter layer)
- NO provider coupling (scatter/retrieve are game-layer concerns)
- NO dynamic depth adjustment beyond MAX_DEPTH

## 6. Design Considerations

### 6A. Fragmenter  -  Why Knuth multiplicative hash?
Knuth's `floor(phi * 2^32)` (where phi = golden ratio  ~  1.618) provides optimal distribution for linear congruential generators. The multiplier `2654435769` is the standard 32-bit golden ratio multiplier  -  no collisions for sequences up to 2^32.

### 6B. Fragmenter  -  Why base-36 encoding?
Compact, alphanumeric, filesystem-safe. Vant uses it for `vfragment-{key}-{shard}.json` naming.

### 6C. Fragmenter  -  Why XOR spreading?
Each fragment appears as random noise. No fragment alone can reconstruct data (XOR with different pattern per shard). Welding reverses it exactly.

### 6D. Fragmenter  -  Stateless architecture
The fragmenter has NO state. Given the same inputs, it produces the same outputs. This enables:
- Deterministic retrieval without a central manifest
- Multiple independent fragmentations of the same data
- Easy testing (pure functions)

### 6E. Fragmenter  -  No scatter/retrieve/incinerate
Vant's `scatter`, `retrieve`, `incinerate` couple to filesystem/Git providers. The frame only needs the core primitives: `derive_lattice_keys`, `fragment`, `weld`. Provider integration is a game-layer concern (Phase 4 edge shards).

### 6F. Spatial Fragmenter  -  Why 64-bit addresses?
- Bitwise operations are orders of magnitude faster than string concatenation during 20Hz frame ticks
- Fixed-width fields eliminate hash collisions (e.g., `1-12` vs `11-2`)
- Face + depth + spatial offsets fit cleanly in 64 bits

### 6G. Spatial Fragmenter  -  Why integer/quantized math?
- Floating-point rounding differs across hardware (float32/float64, GPU/CPU)
- Integer coordinates guarantee identical boundaries on client and server
- No seam cracks at cell boundaries

### 6H. Spatial Fragmenter  -  Why octree-style subdivision?
- 8 children per step is a clean power-of-two split
- Bounding boxes are trivial to compute from quantized offsets
- Depth maps directly to LOD level

### 6I. Spatial Fragmenter  -  Why MAX_DEPTH = 24?
- 2^24  ~  16.7M subdivisions per axis  -  far beyond any practical spatial need
- Prevents infinite recursion from pathological input
- Keeps tick latency bounded

### 6J. Spatial Fragmenter  -  NSC-9 [U+2194] ICosahedral Mapping
**Face encoding question:** NSC-9 uses prefix=9 with facility/axis/sequence (9-AAA-BBB-CCCCCC). Icosahedral projection has 20 triangular faces. The spatial fragmenter uses generic 8-bit face codes (0-255); callers interpret based on context:
- NSC-9 facility  ->  fragmenter face mapping is caller-defined
- Icosahedral vertex index (0-11)  ->  can map to faces 0-11, leaving 8-19 for other region types
- Current design: generic 8-bit region type; caller resolves interpretation

### 6K. Integration Bridge: Fragmenter <-> SpatialFragmenter <-> T3
**Implemented via `Nsc9Bridge`** (`game/core/frame/geometry/nsc9_bridge.gd`):

```gdscript
var bridge := Nsc9Bridge.new()
var address := bridge.nsc9_to_address(nsc_code)
var path := bridge.address_to_t3_path(address)
var hash := bridge.store_nsc9_state(t3, nsc_code, state_dict)
var results := bridge.query_nsc9_face(t3, nsc_code)
```

The bridge connects three frame primitives into a unified pipeline:
- NSC-9 spatial code (64-bit GS1 reservation)
    -> SpatialFragmenter 64-bit address (octree subdivision)
    -> T3 content-hash tree (deterministic state storage)

Pure functions: no state, no autoload, no GameManager dependency.
See `labs/prd-geometry.md` sec. 6K for the original wiring pattern spec.

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `int`, `Array`, `Dictionary`, bitwise ops)
- **Math:** `int` handles 64-bit; mask with `0xFFFFFFFF` to simulate 32-bit overflow where needed
- **32-bit wraparound:** GDScript `int` is 64-bit; use `& 0xFFFFFFFF` for 32-bit simulation
- **Tests:** co-located `test_fragmenter.gd` + `test_spatial_fragmenter.gd`, run with headless Godot
- **Vant lineage:** file headers include Vant credit
- **UTF-8 compliance:** NO special characters in source (per AGENTS.md code standards)

## 8. Success Metrics

### Fragmenter
- [ ] All 3 functions implemented (`derive_lattice_keys`, `fragment`, `weld`)
- [ ] Test file passes ( >=  20 assertions covering all user stories + edge cases)
- [ ] Round-trip fragment + weld recovers exact original for: empty string, "hello", JSON object, 100KB binary, non-ASCII UTF-8 ("[U+4F60][U+597D][U+4E16][U+754C] [U+1F30D]"), variable num_fragments (2, 5, 10)
- [ ] `derive_lattice_keys(12345, 5)` produces stable, distinct keys across runs
- [ ] `derive_lattice_keys(-1, 3)` produces deterministic keys (negative sequence handling)
- [ ] Checksum verification in `weld()` works: corrupting fragment data  ->  checksum mismatch detected, fragment skipped

### Spatial Fragmenter
- [ ] All 11 functions implemented (make_address through generate_key)
- [ ] Test file passes ( >=  40 assertions covering all user stories + edge cases)
- [ ] Deterministic subdivision verified across repeated runs
- [ ] No floating-point values in bounding boxes
- [ ] No address key collisions for distinct addresses
- [ ] MAX_DEPTH prevents fragment explosion

### Cross-Layer Integration
- [x] `labs/world-building-arch.md` sec. 13 component map updated: "Vant fragmenter"  ->  DONE
- [x] `labs/world-building-arch.md` sec. 13 component map updated: "Spatial geometry fragmenter"  ->  DONE
- [x] `labs/world-building-arch.md` sec. 14 migration roadmap: "Vant icosahedral + fragmenter ports"  ->  DONE
- [x] Integration bridge: NSC-9  ->  SpatialFragmenter  ->  T3 wiring documented and implemented via `Nsc9Bridge`
- [x] Single commit, conventional message format

## 9. Open Questions

### Fragmenter (existing, unchanged)
1. **Sequence source:** In production, the sequence comes from the seed chain. `seed_chain.gd::derive_seed()` returns `PackedByteArray` (32-byte SHA-256). Use `int.from_bytes(seed.slice(0, 4), false)` to convert first 4 bytes to a 32-bit int, or hash the full NSC-9 barcode to 32-bit for fragmenter input.
2. **Fragment size ceiling:** Vant uses `Math.ceil(bytes / numFragments)`. GDScript `ceil()` works identically.
3. **Base-36 in GDScript:** `int.to_string(36)` works for positive ints. Need to handle unsigned 32-bit  ->  string. Current `itoa()` implementation handles this.

### Spatial Fragmenter (new)
4. **NSC-9  ->  Face mapping:** RESOLVED via `Nsc9Bridge` / `SpatialFragmenter.nsc9_axis_to_face()`. NSC-9 spatial axis 1-12 maps to faces 0-11; non-spatial axes return -1.
5. **Icosahedral [U+2194] SpatialFragmenter integration:** icosahedral projection returns vertex index 0-11. Should subdivision use octree (8 children) or barycentric (4 children)? Current design: octree for clean bounding boxes; barycentric is a future extension.
6. **T3 path naming convention:** RESOLVED via `SpatialFragmenter.path_for_address()`: `"spatial/%04x-%04x-%04x-d%d-f%d" % [x, y, z, depth, face]`.
7. **Cross-service address sharing:** Should spatial fragmenter addresses be shared across services (e.g., EntityService uses them for positioning, QoSService uses them for range queries)? Currently: pure functions; integration pattern per service.

## 10. Definition of Done

### Fragmenter
- [ ] `game/core/frame/geometry/fragmenter.gd` created with 3 functions + constant
- [ ] `game/core/frame/geometry/test_fragmenter.gd` created and passing
- [ ] `labs/world-building-arch.md` sec. 13 component map: "Vant fragmenter" row status  ->  DONE
- [ ] `labs/world-building-arch.md` sec. 14 migration roadmap: "Vant icosahedral + fragmenter ports"  ->  DONE
- [ ] File headers include Vant lineage credit
- [ ] Smoke test: derive keys  ->  fragment "test"  ->  weld  ->  equals "test"
- [ ] One commit to main

### Spatial Fragmenter
- [ ] `game/core/frame/geometry/spatial_fragmenter.gd` created with all functions
- [ ] `game/core/frame/geometry/test_spatial_fragmenter.gd` created and passing
- [ ] `labs/world-building-arch.md` sec. 13 component map: "Spatial geometry fragmenter"  ->  DONE
- [ ] File headers include Vant/vant lineage credit where applicable
- [ ] Smoke test: subdivide  ->  parent  ->  ancestor  ->  bounding box  ->  key
- [ ] One commit to main

### Cross-Layer
- [ ] Integration bridge documented in PRD
- [ ] No ASCII/UTF-8 violations in any new file
- [ ] Both test suites run with `godot --headless --path . --script ...`