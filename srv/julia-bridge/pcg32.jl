"""
pcg32.jl — a faithful Julia port of Godot 4.7.2's RandomNumberGenerator.

Godot's RNG is PCG32 (Melissa O'Neill's permuted congruential generator)
with a fixed increment. The frame's prop scatter (terrain_gen.rock_specs /
boulder_specs) seeds one RNG per face and draws counts, barycentric
vertices, scales and yaws; to reproduce those specs offline the Julia
tier must consume the SAME stream bit for bit.

Cracked from Godot's core/math/random_pcg.h + thirdparty/misc/pcg.h:

  * multiplier  M   = 6364136223846793005 (0x5851F42D4C957F2D)
  * increment   INC = 1442695040888963407 (0x14057B7EF767814F)
  * seed(s):  state = 0; step; state += s; step   (pcg32_srandom_r with
    inc = PCG_DEFAULT_INC_64, i.e. (INC << 1) | 1)
  * randi():  output is computed from the OLD state (xorshift + rotate),
    THEN the state advances. This "output old state" ordering is what the
    GDScript randi()/randf() callers observe.
  * randf():  proto = randi(); if proto == 0 -> 0.0; else
              sig = (float)(randi() | 0x80000001);
              randf = ldexpf(sig, -32 - clz32(proto)).
    The exponent is stolen from a SEPARATE random draw (CLZ of it), which
    is why a naive (r / 2^32) port never matched.

The GDScript frame stays authoritative; tests/test_julia_prop_batch.gd
validates this output against it.

NOTE (this container's Julia build): type-annotated `const` globals and
bare last-expression returns inside `::T`-typed methods can SEGFAULT the
compiler, so this file keeps consts untyped and every method body ends in
an explicit `return`.
"""
module PCG32

const MULT = 0x5851F42D4C957F2D
const DEFAULT_INC = 0x14057B7EF767814F

mutable struct Rng
    state::UInt64
    inc::UInt64
end

## Seed exactly as RandomNumberGenerator.seed = s does.
function Rng(seed::Integer)::Rng
    inc = (DEFAULT_INC << 1) | UInt64(1)
    st = UInt64(0)
    st = st * MULT + inc
    st = st + (UInt64(seed) % UInt64)
    st = st * MULT + inc
    return Rng(st, inc)
end

## randi(): the 32-bit output of the OLD state, then advance.
## The `& 0xFFFFFFFF` mirrors C's implicit uint32_t truncation of the
## xorshift result (Godot: `uint32_t xorshifted = ...`); without it
## Julia's checked UInt32() conversion throws (and crashes this build).
function rand_u32(r::Rng)::UInt32
    old = r.state
    r.state = old * MULT + r.inc
    xs  = UInt32((((old >> 18) ⊻ old) >> 27) & 0xFFFFFFFF)
    rot = UInt32(old >> 59)
    return (xs >> rot) | (xs << ((-rot) & UInt32(31)))
end

## randf() in [0, 1): CLZ-stolen exponent over a second draw.
@inline function rand_f32(r::Rng)::Float32
    proto = rand_u32(r)
    if proto == UInt32(0)
        return 0.0f0
    end
    sig = Float32(rand_u32(r) | UInt32(0x80000001))
    exp = -32 - Int(leading_zeros(proto))
    return ldexp(sig, exp)
end

## randf_range(from, to) = randf() * (to - from) + from, in float32.
@inline function rand_f32_range(r::Rng, from::Float32, to::Float32)::Float32
    return rand_f32(r) * (to - from) + from
end

## randi_range(from, to): pcg32_boundedrand_r, rejection then modulo.
function randi_range(r::Rng, from::Integer, to::Integer)::Int64
    bound = UInt32(to - from + 1)
    threshold = (UInt32(0) - bound) % bound
    while true
        v = rand_u32(r)
        if v >= threshold
            return Int64(from) + Int64(v % bound)
        end
    end
end

end # module PCG32
