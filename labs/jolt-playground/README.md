# labs/jolt-playground/ — Jolt Physics Playground

**The plan:** Benchmark Jolt Physics as a swap-in replacement
for Godot Physics 3D. Decide before Phase 5 (World Building)
whether to ship with Jolt.

---

## Why Jolt

Jolt is a C++ physics engine by **Jorrit Rouwe** (Guerrilla
Games — Horizon Zero Dawn, Death Stranding, Ratchet & Clank).
MIT licensed. The Godot integration is **godot-jolt** by Mikael
Lindqvist, now a first-class option in Godot 4.3+ via
`Project Settings → Physics → 3D → Physics Engine`.

| Property | Godot Physics (default) | Jolt |
|----------|------------------------|------|
| Speed at scale (many bodies) | OK at low counts, chokes on hundreds | Linear, multi-threaded |
| Character controllers | Sliding/jittery on slopes | Stable, predictable |
| Determinism | Floating-point drift | Float-deterministic on the same hardware |
| Continuous collision (fast movers) | Optional, expensive | Default, fast |
| Threading | Mostly main thread | Job-based, scales with cores |

## Why it specifically matters for Synmergia

The new state tree is content-hashed. **Server tick = re-root.
Client sync = diff between hashes.** That depends on physics
being deterministic enough that two systems running the same
simulation land on the same hash. Godot Physics drifts more
than Jolt does.

The other thing: B-9 (the perf budget session) is the right
time to decide. If Jolt is the answer, you swap `PhysicsServer3D`
calls for the Jolt equivalents and the game logic doesn't
change. The orchestrator + state tree are physics-agnostic.

## What this playground will contain

```
labs/jolt-playground/
├── README.md                       # this file
├── design.md                       # long-form design
├── scenes/                         # synthetic stress tests
│   ├── stress_1k.tscn              # 1000 dynamic bodies
│   ├── stress_10k.tscn             # 10000 dynamic bodies
│   ├── stack_collapse.tscn         # determinism check
│   └── character_walk.tscn         # controller stability
├── scripts/
│   ├── stress_runner.gd            # drives the scene, logs stats
│   ├── hash_collector.gd           # samples world state to hash
│   └── compare.gd                  # compares Godot vs Jolt hash
├── reports/                        # generated benchmark results
│   ├── 1k_godot.txt
│   ├── 1k_jolt.txt
│   ├── 10k_godot.txt
│   └── 10k_jolt.txt
└── decision.md                     # "use Jolt" or "use Godot Physics"
```

The decision document is the deliverable. The benchmarks feed
it.

## When this is needed

- **Now:** speculative. The POC doesn't have enough entities
  to need Jolt.
- **Phase 1 (State tree + Track A):** still not needed.
- **Phase 2 (Vertical Slice):** first time we have 100+ NPCs
  in a zone. Early Jolt experiment possible here.
- **Phase 5 (World Building):** entity count crosses 10K in
  contested zones. **Decision deadline.**
- **Phase 6 (MMO Features):** if not done by here, MMO
  density will be painful.

## How to swap

In Godot 4.3+, the swap is one setting:
`Project Settings → Physics → 3D → Physics Engine = Jolt Physics`.

For older versions or custom builds, install the
[godot-jolt](https://github.com/godot-jolt/godot-jolt) plugin.

The game code is physics-agnostic — we use
`PhysicsServer3D` and `RigidBody3D` everywhere. Jolt implements
the same interface.

## The benchmark we actually care about

Not frame time. **Hash determinism.**

```
1. Initialize scene with N dynamic bodies
2. Run physics for 60 seconds at 60 Hz
3. Hash the entire world state
4. Reset, run again
5. Compare hashes
```

If Godot Physics produces different hashes for the same scene
+ same inputs, our state tree can't trust it. If Jolt produces
the same hashes, we have a foundation for the content-hash
state tree.

## Status

- [x] Design intent
- [ ] Benchmark scene scripts
- [ ] First-pass numbers (1K, 10K)
- [ ] Determinism comparison
- [ ] Decision document

The benchmark is small (~200 lines of GDScript per scene).
Total budget: 1-2 sessions to land.

## References

- [Jolt repo](https://github.com/jrouwe/JoltPhysics) — the engine
- [godot-jolt](https://github.com/godot-jolt/godot-jolt) — the Godot plugin
- Jorrit Rouwe's GDC talk on Jolt's design
