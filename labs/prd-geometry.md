# PRD: Geometry Layer — Vant Fragmenter Port

> **For:** sub-agent implementation
> **Phase:** 4 (per `world-building-arch.md` §11.4, §14)
> **Depends on:** `prd-t3-substrate.md` (for content-hash keys), `prd-seed-schema.md` (for sequence derivation), `world-building-arch.md` §16 (Vant geometric addressing)
> **Unblocks:** Edge shards (§11.4), shard partitioning via lattice keys

## 1. Introduction/Overview

The geometry layer ports Vant's aperiodic quasicrystal memory addressing into the frame. The fragmenter specifically handles **stateless data sharding** via Knuth's multiplicative hash — no central manifest, no lookup tables. Given a sequence (barcode, seed, or hash), it deterministically derives N lattice keys and fragments data across them.

**Why this exists:** Per arch doc §16, Vant's `fragmenter.js` provides the lattice key derivation and fragmentation logic that the frame uses for:
- Shard partitioning in Phase 4+ edge shards
- Content distribution across multi-provider storage
- Aperiodic address space for state trees (future)

**Spec refs:**
- [`world-building-arch.md`](./world-building-arch.md) §16 (Geometric addressing)
- [`world-building-arch.md`](./world-building-arch.md) §13 Component map row "Vant fragmenter"
- [`prd-t3-substrate.md`](./prd-t3-substrate.md) (content-hash keys map to lattice keys)

## 2. Goals

- ONE `fragmenter.gd` in `game/core/frame/geometry/` — pure functions, no state
- Implement Vant's `deriveLatticeKeys`, `fragment`, `weld` (core API)
- Knuth multiplicative hash with `LATTICE_MULTIPLIER = floor(φ * 2^32) = 2654435769`
- Stateless: no lookup tables, no central manifest, no provider coupling
- Co-located test file `test_fragmenter.gd` covering all functions
- File header: `## Ported from vant axolotl lib/geometry/fragmenter.js`

## 3. User Stories

### US-001: Lattice key derivation

**Description:** As a developer, I need a `derive_lattice_keys(sequence: int, num_fragments: int = 5) -> Array[String]` function that deterministically derives N aperiodic lattice keys from a single sequence integer, so state can be addressed without a central index.

**Acceptance Criteria:**
- [ ] Function exists in `game/core/frame/geometry/fragmenter.gd`
- [ ] Uses `LATTICE_MULTIPLIER = 2654435769` (Knuth's `floor(φ * 2^32)`)
- [ ] Returns `Array[String]` of length `num_fragments` (base-36 encoded)
- [ ] Deterministic: same sequence + same num_fragments → same keys
- [ ] Progressive keystream: key[i] derived from `(baseHash + i) * MULTIPLIER`
- [ ] Test: `derive_lattice_keys(12345, 5)` produces stable, distinct keys

### US-002: Data fragmentation

**Description:** As a developer, I need a `fragment(data: Variant, num_fragments: int = 5) -> Array[Dictionary]` function that splits arbitrary data into N fragments with XOR spreading, so no single fragment reveals the original data.

**Acceptance Criteria:**
- [ ] Function exists in `fragmenter.gd`
- [ ] Accepts `Variant` (string, dict, array, etc.) — JSON stringifies non-strings
- [ ] Returns `Array[Dictionary]` with keys: `shard` (int), `data` (base64 String), `size` (int), `checksum` (int)
- [ ] Approximate equal byte distribution across fragments
- [ ] XOR spreading: each byte XOR'd with `((shard + 1) * 137 >> 5)`
- [ ] Checksum: `sum(byte * (i + 1)) % 65536` per fragment
- [ ] Test: round-trip fragment + weld recovers original data exactly

### US-003: Fragment welding

**Description:** As a developer, I need a `weld(fragments: Array) -> String` function that reconstructs original data from fragments, so retrieval is deterministic and order-independent.

**Acceptance Criteria:**
- [ ] Function exists in `fragmenter.gd`
- [ ] Accepts fragments as `Array[Dictionary]` (with `shard`, `data`) OR `Array[String]` (base64 only, infers shard from index)
- [ ] Sorts by `shard` before decoding
- [ ] Reverses XOR spreading: `decoded[i] ^ ((shard + 1) * 137 >> 5)`
- [ ] Concatenates and returns UTF-8 string
- [ ] Test: weld(fragment("hello world", 3)) == "hello world"

### US-004: Test coverage

**Description:** As a developer, I need a co-located test file `test_fragmenter.gd` that validates all three functions, so regressions are caught.

**Acceptance Criteria:**
- [ ] Test file at `game/core/frame/geometry/test_fragmenter.gd`
- [ ] Tests: derive_lattice_keys deterministic, fragment/weld round-trip, variable num_fragments (2, 5, 10), empty data, large data (>10KB)
- [ ] Runs with `godot --headless --path . --script res://core/frame/geometry/test_fragmenter.gd`
- [ ] Exit code 0 on pass, non-zero on fail

## 4. Functional Requirements

- **FR-1:** Single file `game/core/frame/geometry/fragmenter.gd` with three static functions
- **FR-2:** Constant `LATTICE_MULTIPLIER = 2654435769`
- **FR-3:** `derive_lattice_keys(sequence: int, num_fragments: int = 5) -> Array[String]`
- **FR-4:** `fragment(data: Variant, num_fragments: int = 5) -> Array[Dictionary]`
- **FR-5:** `weld(fragments: Array) -> String`
- **FR-5:** NO autoload, NO class_name, NO GameManager dependency (per AGENTS.md frame primitive rules)
- **FR-6:** NO external dependencies beyond Godot stdlib
- **FR-7:** Tests in co-located `test_fragmenter.gd`

## 5. Non-Goals (Out of Scope)

- NO provider coupling (scatter/retrieve/incinerate are Vant-specific Git multi-provider ops; not needed in frame)
- NO async/await (pure synchronous functions)
- NO encryption (XOR spreading is obfuscation, not crypto; encryption is a higher layer)
- NO manifest/index (stateless by design)
- NO icosahedral/Penrose/quasicrystal math (those are separate math primitives in `game/core/frame/math/`)
- NO persistent state (functions are pure)

## 6. Design Considerations

### Why Knuth multiplicative hash?
Knuth's `floor(φ * 2^32)` (where φ = golden ratio ≈ 1.618) provides optimal distribution for linear congruential generators. The multiplier `2654435769` is the standard 32-bit golden ratio multiplier — no collisions for sequences up to 2^32.

### Why base-36 encoding?
Compact, alphanumeric, filesystem-safe. Vant uses it for `vfragment-{key}-{shard}.json` naming.

### Why XOR spreading?
Each fragment appears as random noise. No fragment alone can reconstruct data (XOR with different pattern per shard). Welding reverses it exactly.

### Stateless architecture
The fragmenter has NO state. Given the same inputs, it produces the same outputs. This enables:
- Deterministic retrieval without a central manifest
- Multiple independent fragmentations of the same data
- Easy testing (pure functions)

### No scatter/retrieve/incinerate
Vant's `scatter`, `retrieve`, `incinerate` couple to filesystem/Git providers. The frame only needs the core primitives: `derive_lattice_keys`, `fragment`, `weld`. Provider integration is a game-layer concern (Phase 4 edge shards).

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `int`, `Array`, `Dictionary`, `to_base64()`, `to_utf8()`, bitwise ops)
- **Math:** `Math.imul` equivalent in GDScript → `int` handles 64-bit, use `<<`, `>>`, `^`, `&`
- **32-bit wraparound:** GDScript `int` is 64-bit; mask with `0xFFFFFFFF` to simulate 32-bit overflow
- **Tests:** co-located `test_fragmenter.gd`, run with headless Godot
- **Vant lineage:** file header `## Ported from vant axolotl lib/geometry/fragmenter.js`

### 32-bit math in GDScript
```gdscript
const LATTICE_MULTIPLIER = 2654435769  # 0x9E3779B9

func _imul(a: int, b: int) -> int:
    # Simulate 32-bit signed multiplication
    return ((a * b) & 0xFFFFFFFF)
```

### Key derivation algorithm (from Vant)
```javascript
const baseHash = Math.imul(sequence, LATTICE_MULTIPLIER);
for (let i = 0; i < numFragments; i++) {
    const key = Math.imul((baseHash >>> 0) + i, LATTICE_MULTIPLIER);
    keys.push(((key >>> 16) ^ (key >>> 0)).toString(36));
}
```

## 8. Success Metrics

- All 3 functions implemented and pushed to main
- Test file passes (≥ 15 assertions covering all user stories)
- Round-trip fragment + weld recovers exact original for: empty string, "hello", JSON object, 100KB binary
- `derive_lattice_keys(12345, 5)` produces stable output across runs
- `game/core/frame/geometry/` directory exists with `fragmenter.gd` + `test_fragmenter.gd`
- `labs/world-building-arch.md` §13 component map updated: "Vant fragmenter" → DONE
- `labs/world-building-arch.md` §14 migration roadmap updated: "Vant icosahedral + fragmenter ports" → DONE
- Single commit, conventional message format

## 9. Open Questions

1. **Sequence source:** In production, the sequence comes from the seed chain (barcode integer). For testing, any positive int works. The PRD assumes `sequence: int` — caller resolves barcode→int.
2. **Fragment size ceiling:** Vant uses `Math.ceil(bytes / numFragments)`. GDScript `ceil()` works identically.
3. **Base-36 in GDScript:** `int.to_string(36)` works for positive ints. Need to handle unsigned 32-bit → string.

## 10. Definition of Done

- [ ] `game/core/frame/geometry/fragmenter.gd` created with 3 functions + constant
- [ ] `game/core/frame/geometry/test_fragmenter.gd` created and passing
- [ ] `labs/world-building-arch.md` §13 component map: "Vant fragmenter" row status → DONE
- [ ] `labs/world-building-arch.md` §14 migration roadmap: "Vant icosahedral + fragmenter ports" → DONE
- [ ] `labs/prd-geometry.md` linked from `labs/README.md` (PRD list)
- [ ] File headers include Vant lineage credit
- [ ] Smoke test: derive keys → fragment "test" → weld → equals "test"
- [ ] One commit to main