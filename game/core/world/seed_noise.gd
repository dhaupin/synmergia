## SeedNoise -- deterministic, seed-derived smooth fields for conjured
## worlds (labs/prd-clipmap.md section 10). The main world's climate hides in
## `TerrainGen`'s closed form; a smaller globe (the underworld, the moon)
## can afford its own honest truth: a band-limited sum of sine waves whose
## axes/phases/frequencies derive from the world seed. Every read is a PURE
## function of (seed_acc, dir, salt) -- no RNG state, no accumulation -- so a
## world re-derives byte-identical on every machine and every boot.
##
## Frame-agnostic (no autoload, no class_name): instantiated by path or used
## through its statics.
extends RefCounted


## Fold 32 seed bytes into a stable non-negative 64-bit-ish accumulator.
static func seed_accumulator(seed: PackedByteArray) -> int:
        var acc: int = 0
        for b in seed:
                acc = (acc * 256 + b) % 9007199254740991
        return acc


## A stable [0,1) value from an integer hash (an LCG-style finalizer;
## constants kept below 2^62 so GDScript's signed 64-bit literals parse --
## overflow wraps deterministically, which is exactly what a hash wants).
static func hash01(h: int) -> float:
        h = h * 6364136223846793005 + 1442695040888963407
        h = h ^ (h >> 29)
        h = h * 2862933555777941757 + 3037000493
        h = h ^ (h >> 32)
        return float(h & 0xFFFFFF) / 16777216.0


## A derived [0,1) value for (seed_acc, salt, index) -- the axis/phase/freq
## drawer. Pure: same inputs, same value, every machine.
static func value(seed_acc: int, salt: int, index: int) -> float:
        var h: int = seed_acc
        h = h * 1000003 ^ (salt * 2654435761)
        h = h * 1000003 ^ (index * 40503)
        return hash01(h)


## A smooth band-limited height field on the unit sphere: `octaves` sine
## waves whose axes/phase/frequency derive from the seed. Returns roughly
## [-1, 1]; callers scale it to metres. Continuous everywhere (a direction
## change moves every term smoothly), so the clipmap draws rolling ground,
## never a noise wall.
static func smooth_field(dir: Vector3, seed_acc: int, salt: int, octaves: int) -> float:
        var d: Vector3 = dir.normalized()
        var total: float = 0.0
        var amp: float = 1.0
        var norm: float = 0.0
        var freq: float = 1.4
        for o in range(octaves):
                # A pseudo-axis from the seed (an arbitrary unit vector), so
                # waves run in varied directions rather than all along +Y.
                var ax: float = value(seed_acc, salt, o * 4 + 0) * 2.0 - 1.0
                var ay: float = value(seed_acc, salt, o * 4 + 1) * 2.0 - 1.0
                var az: float = value(seed_acc, salt, o * 4 + 2) * 2.0 - 1.0
                var axis := Vector3(ax, ay, az)
                if axis.length() < 0.001:
                        axis = Vector3(0, 1, 0)
                axis = axis.normalized()
                var phase: float = value(seed_acc, salt, o * 4 + 3) * TAU
                total += amp * sin(d.dot(axis) * freq + phase)
                norm += amp
                amp *= 0.55
                freq *= 1.9
        if norm <= 0.0:
                return 0.0
        return total / norm
