"""
terrainmath.jl — pure-Julia mirror of TerrainGen's analytic RAW heightfield.

The frame's ground law is a pure function of (unit_dir, seed_bytes):
`TerrainGen._natural_raw(d, seed)`. That is exactly the shape a
pre-solve/backend tier wants — evaluate a whole batch of directions in
one call, pay the round-trip once. This module mirrors ONLY the raw
analytic field (the body `install_terrain_backend` replaces); the frame
still applies `_sculpt_and_spawn` + the hydrology carve on top, so the
island/moat/plaza guarantees and the rivers/lakes stay law-native.

Mirrored 1:1 from `game/scenes/worlds/terrain_gen.gd`:
  _seed_salt / sea_level / _cell_hash / _vnoise
  _land_mass / _homeland / _polar_cap / _sun_pans_island / _lake_bowl
  _natural_raw (the raw band law)

The GDScript frame stays authoritative; `tests/test_julia_terrain.gd`
validates this output against it (float32 tolerance: the frame's
Vector3 math is float32, this is float64).
"""
module TerrainMath

# ---------------------------------------------------------------- constants
const PHI = 1.6180339887498949

# Spawn / site anchors (terrain_gen.gd).
const SPAWN_CENTER = (1.0, 0.0, 0.0)
const LAKE_CENTER  = (0.28, 0.26, 0.92)
const LAKE_RADIUS_ANG = 0.055
const LAKE_DROP = 7.5
const HOMELAND_ANGULAR_REACH = 0.70
const POLAR_CAP_ANG = 0.34
const SUN_PANS_ANG = 0.028
const SUN_PANS_DIR = (-0.57735025882720947, 0.57735025882720947, -0.57735025882720947)

# Bands.
const MOUNTAIN_AMP = 1000.0
const RING_R0 = 0.26
const RING_R1 = 0.46
const RING_R2 = 0.74
const RING_T_LO = 0.35
const RING_T_HI = 0.55
const POLAR_RELIEF_AMP = 420.0
const TERRAIN_MAX = 560.0
const SEA_LEVEL_MIN = 4.0
const SEA_LEVEL_SPAN = 3.0
const OCEAN_DEPTH_MIN = 9.0
const OCEAN_DEPTH_SPAN = 6.0

const HASH_MOD = 1000003

# ---------------------------------------------------------------- vector ops
@inline dot3(a, b) = a[1]*b[1] + a[2]*b[2] + a[3]*b[3]
@inline function norm3(a)
    l = sqrt(dot3(a, a))
    l == 0.0 ? (0.0, 0.0, 0.0) : (a[1]/l, a[2]/l, a[3]/l)
end
@inline cross3(a, b) = (a[2]*b[3] - a[3]*b[2], a[3]*b[1] - a[1]*b[3], a[1]*b[2] - a[2]*b[1])
@inline sub3(a, b) = (a[1]-b[1], a[2]-b[2], a[3]-b[3])
@inline scale3(a, s) = (a[1]*s, a[2]*s, a[3]*s)
@inline add3(a, b) = (a[1]+b[1], a[2]+b[2], a[3]+b[3])

# Godot Vector3.angle_to: acos(clamp(dot(na, nb), -1, 1)).
@inline function angle_to(a, b)
    na = norm3(a); nb = norm3(b)
    acos(clamp(dot3(na, nb), -1.0, 1.0))
end

# ---------------------------------------------------------------- scalar law
@inline smoothstep(from, to, x) = begin
    t = clamp((x - from) / (to - from), 0.0, 1.0)
    t * t * (3.0 - 2.0 * t)
end
@inline lerp(a, b, t) = a + (b - a) * t

# _seed_salt: fold tag bytes then seed bytes with acc = (acc*131 + b) % (2^53-1).
const SALT_MOD = 9007199254740991
function seed_salt(seed::Vector{UInt8}, tag::AbstractString)::Int64
    acc::Int64 = 0
    for b in codeunits(tag)
        acc = (acc * 131 + Int64(b)) % SALT_MOD
    end
    for b in seed
        acc = (acc * 131 + Int64(b)) % SALT_MOD
    end
    return acc
end

# sea_level: 4.0 + 3.0 * fposmod(seed_salt(seed,"sea"), 1000003) / 1000003.
function sea_level(seed::Vector{UInt8})::Float64
    v = Float64(seed_salt(seed, "sea"))
    SEA_LEVEL_MIN + SEA_LEVEL_SPAN * mod(v, Float64(HASH_MOD)) / Float64(HASH_MOD)
end

# _cell_hash: wrapping 64-bit int hash -> [0,1).
@inline function cell_hash(cell, salt::Int64)::Float64
    h::Int64 = salt
    h = (h * 668265263) ⊻ (Int64(cell[1]) * 374761393)
    h = (h * 1274126177) ⊻ (Int64(cell[2]) * 668265263)
    zterm::Int64 = Int64(cell[3]) * 2147483647 + 7919
    h = (h * 974634733) ⊻ (zterm ⊻ (zterm >> 13))
    h = h ⊻ (h >> 15)
    h = h ⊻ (h >> 33)
    return Float64(abs(h) % HASH_MOD) / Float64(HASH_MOD)
end

# _vnoise: trilinear value noise on the direction cube.
@inline function vnoise(d, salt::Int64, freq::Float64)::Float64
    p = scale3(d, freq)
    c = (floor(Int64, p[1]), floor(Int64, p[2]), floor(Int64, p[3]))
    f = (p[1] - c[1], p[2] - c[2], p[3] - c[3])
    u = (f[1]*f[1]*(3.0 - 2.0*f[1]),
         f[2]*f[2]*(3.0 - 2.0*f[2]),
         f[3]*f[3]*(3.0 - 2.0*f[3]))
    v000 = cell_hash((c[1],   c[2],   c[3]  ), salt)
    v100 = cell_hash((c[1]+1, c[2],   c[3]  ), salt)
    v010 = cell_hash((c[1],   c[2]+1, c[3]  ), salt)
    v110 = cell_hash((c[1]+1, c[2]+1, c[3]  ), salt)
    v001 = cell_hash((c[1],   c[2],   c[3]+1), salt)
    v101 = cell_hash((c[1]+1, c[2],   c[3]+1), salt)
    v011 = cell_hash((c[1],   c[2]+1, c[3]+1), salt)
    v111 = cell_hash((c[1]+1, c[2]+1, c[3]+1), salt)
    x00 = lerp(v000, v100, u[1]); x10 = lerp(v010, v110, u[1])
    x01 = lerp(v001, v101, u[1]); x11 = lerp(v011, v111, u[1])
    return lerp(lerp(x00, x10, u[2]), lerp(x01, x11, u[2]), u[3])
end

# ---------------------------------------------------------------- shape fields
function homeland(d)::Float64
    ang = angle_to(d, SPAWN_CENTER)
    ang >= HOMELAND_ANGULAR_REACH && return 0.0
    t = ang / HOMELAND_ANGULAR_REACH
    t <= 0.6 ? 1.0 : smoothstep(1.0, 0.6, t)
end

function polar_cap(d)::Float64
    ang = acos(clamp(abs(d[2]), -1.0, 1.0))
    ang >= POLAR_CAP_ANG && return 0.0
    t = ang / POLAR_CAP_ANG
    t <= 0.6 ? 1.0 : smoothstep(1.0, 0.6, t)
end

function sun_pans_island(d)::Float64
    ang = angle_to(d, SUN_PANS_DIR)
    ang >= SUN_PANS_ANG && return 0.0
    t = ang / SUN_PANS_ANG
    t <= 0.55 ? 1.0 : smoothstep(1.0, 0.55, t)
end

function lake_bowl(d)::Float64
    ang = angle_to(d, LAKE_CENTER)
    ang >= LAKE_RADIUS_ANG && return 0.0
    smoothstep(0.0, 1.0, 1.0 - ang / LAKE_RADIUS_ANG)
end

# _land_mass: latitude band gate x continental noise, plus the authored domes.
function land_mass(d, salt::Int64)::Float64
    lat = 90.0 - rad2deg(acos(clamp(d[2], -1.0, 1.0)))
    band = clamp(cos(deg2rad(min(abs(lat), 45.0) * (90.0 / 45.0))), 0.0, 1.0)
    base = vnoise(d, salt, 2.0)
    detail = 0.65 * vnoise(d, salt + 1, 5.0) + 0.35 * vnoise(d, salt + 2, 11.0)
    noise_land = clamp(band * (base * 1.15 + detail * 0.45 - 0.68), 0.0, 1.0)
    dome = homeland(d)
    if dome > 0.0
        return clamp(max(noise_land, max(dome * 0.95 - detail * 0.35, dome * 0.42)), 0.0, 1.0)
    end
    pans = sun_pans_island(d)
    if pans > 0.0
        return clamp(max(noise_land, max(pans * 0.95 - detail * 0.35, pans * 0.42)), 0.0, 1.0)
    end
    cap = polar_cap(d)
    if cap > 0.0
        return clamp(max(noise_land, max(cap * 1.02 - detail * 0.25, cap * 0.72)), 0.0, 1.0)
    end
    return noise_land
end

# ---------------------------------------------------------------- the raw law
"""
    natural_raw(dir, seed) -> Float64

Mirrors TerrainGen._natural_raw (the analytic landfield, BEFORE the
sculpt/spawn tail and the hydrology carve). `dir` need not be unit;
it is normalized here exactly as the GDScript caller normalizes.
"""
function natural_raw(dir, seed::Vector{UInt8})::Float64
    d = norm3(dir)
    sea = sea_level(seed)
    salt = seed_salt(seed, "terrain")
    land = land_mass(d, salt)

    ocean_floor = sea - (OCEAN_DEPTH_MIN + OCEAN_DEPTH_SPAN * vnoise(d, salt + 7, 6.0))
    land_h = -3.0 + land * 17.0
    inland = smoothstep(0.18, 0.5, land)
    land_h += inland * (vnoise(d, salt + 4, 9.0) * 6.0 - 2.0)

    mnoise = vnoise(d, salt + 3, 3.0)
    mask = smoothstep(0.62, 0.94, mnoise) * smoothstep(0.35, 0.6, land)
    land_h += mask * mnoise^2.2 * MOUNTAIN_AMP

    # The home-anchored ring range (spawn polar frame).
    ang_boot = angle_to(d, SPAWN_CENTER)
    ramp = smoothstep(RING_R0, RING_R1, ang_boot) * (1.0 - smoothstep(RING_R1, RING_R2, ang_boot))
    if ramp > 0.0
        east = norm3(cross3((0.0, 1.0, 0.0), SPAWN_CENTER))
        north = norm3(cross3(SPAWN_CENTER, east))
        phi = atan(dot3(d, north), dot3(d, east))
        pf = (cos(phi), sin(phi), ang_boot)
        crest_noise = vnoise(pf, salt + 21, 0.55)
        crest = 1.0 - abs(2.0 * crest_noise - 1.0)
        blobs = vnoise(pf, salt + 22, 0.9)
        chain_gate = smoothstep(RING_T_LO, RING_T_LO + 0.2, blobs) *
                     (1.0 - smoothstep(RING_T_HI, RING_T_HI + 0.25, blobs))
        land_gate = smoothstep(0.20, 0.34, land)
        land_h += ramp * chain_gate * (0.35 + 0.65 * crest^1.6) * land_gate * MOUNTAIN_AMP
    end

    # The polar relief.
    cap_r = polar_cap(d)
    if cap_r > 0.0
        cap_noise = vnoise(d, salt + 31, 4.0)
        cap_mask = smoothstep(0.55, 0.92, cap_noise) * smoothstep(0.35, 0.7, land)
        land_h += cap_r * cap_mask * cap_noise^2.0 * POLAR_RELIEF_AMP
    end

    h = min(lerp(ocean_floor, land_h, smoothstep(0.0, 0.18, land)), TERRAIN_MAX)
    bowl = lake_bowl(d) * smoothstep(0.1, 0.3, land)
    if bowl > 0.0
        h = lerp(h, sea - LAKE_DROP, bowl)
    end
    return h
end

"""
    heights_batch(dirs, seed) -> Vector{Float64}

Evaluate `natural_raw` for a batch of directions in one call (the whole
point of the tier: one round-trip, N heights).
"""
function heights_batch(dirs::Vector{NTuple{3,Float64}}, seed::Vector{UInt8})::Vector{Float64}
    [natural_raw(d, seed) for d in dirs]
end

end  # module
