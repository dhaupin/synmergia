# Labs: Independent Primitives as the Public API

**TL;DR:** Pull every function, math operation, and prediction
algorithm out of the orchestrator / services / autoloads and into
**independent tools** that the rest of the system USES. The
directory for these is `labs/multi-iso/`. When the frame extracts,
this directory *is* the public API.

The "everyone on the same page" benefit: a developer opens
`labs/multi-iso/`, sees the building blocks, and understands the
system. The "raw-dog" benefit: no embedded abstractions, no
hidden state. The "frame" benefit: when extracted, this directory
is the entire API surface.

---

## The principle

The user said:

> "It is important we pull the functions and math and everything we
> are using to predict out of these flows and into independent tools
> we use. Then we will all be on the same page."

The principle: **primitives are independent; flows compose them.**

In the current Synmergia code, things like the Markov predictor, the
LOD manager, and the content-hash function are sketched inside the
design docs but haven't been written. When they are written, they
should live in `labs/multi-iso/`, not inside `core/services/` or
`core/autoload/`.

The contrast:

```gdscript
# EMBEDDED (what we don't want)
class_name Orchestrator
  var _markov: MarkovChain  # private, untestable in isolation
  
  func predict_next(player):
    return _markov.next(player.history)


# INDEPENDENT (what we want)
# labs/multi-iso/srv/markov.gd
class_name MarkovChain:
  func train(transitions: Array) -> void
  func next(state) -> Variant
  func prob(from_state, to_state) -> float

# core/services/orchestrator.gd
class_name Orchestrator
  var predictor: MarkovChain  # pulled in via the orchestrator's deps

  func predict_next(player):
    return MarkovChain.next(player.history)
```

The MarkovChain is testable in isolation. The orchestrator is
thin and obvious. The "same page" effect: when you see
`MarkovChain` in the orchestrator, you know exactly what it does
because you've read `labs/multi-iso/srv/markov.gd`.

---

## The directory

```
labs/
├── README.md                    # the in-tree convention (root of /labs)
└── multi-iso/                   # the multi-iso frame work
    ├── README.md                # short version of this doc, specific to multi-iso
    ├── math/                    # pure math primitives (no state)
    │   ├── nsc9.gd              # NSC-9 encode/decode/validate
    │   ├── test_nsc9.gd
    │   ├── icosahedral.gd       # projection, depth recursion
    │   ├── test_icosahedral.gd
    │   ├── quasicrystal.gd      # path generation
    │   └── test_quasicrystal.gd
    ├── kv/                      # in-memory data primitives
    │   ├── lru_cache.gd         # generic LRU
    │   ├── test_lru_cache.gd
    │   ├── content_hash.gd      # SHA-256 wrapper
    │   ├── test_content_hash.gd
    │   ├── state_tree.gd        # content-addressed tree
    │   └── test_state_tree.gd
    ├── srv/                     # service logic primitives
    │   ├── markov.gd            # generic Markov chain
    │   ├── test_markov.gd
    │   ├── predictor.gd         # transition probability
    │   ├── test_predictor.gd
    │   ├── composite_table.gd   # LRU-backed materialized intersections
    │   ├── test_composite_table.gd
    │   ├── lod_manager.gd       # promote/demote regions
    │   ├── test_lod_manager.gd
    │   ├── axis.gd              # base class for axes
    │   ├── test_axis.gd
    │   ├── axis_registry.gd     # load axis reservations
    │   └── test_axis_registry.gd
    ├── db/                      # database primitives
    │   ├── snapshot_store.gd    # Postgres integration for state trees
    │   ├── test_snapshot_store.gd
    │   ├── query_builders/      # type-safe query construction
    │   └── migrations/          # schema migrations
    └── tests/                   # cross-cutting tests (if needed)
```

### Why these subdirectories?

- **`math/`** — Pure functions. No state, no side effects. Inputs
  in, outputs out. Examples: NSC-9 parsing, icosahedral projection.
- **`kv/`** — In-memory data structures. LRU, hash table wrappers,
  the state tree itself. Stateful but local.
- **`srv/`** — Service logic that doesn't fit "math" or "kv".
  Markov chain, predictor, orchestrator building blocks. May
  compose math + kv primitives.
- **`db/`** — Anything that talks to a database. Snapshot store,
  query builders, migrations. Includes `migrations/` as a
  subdirectory because schema migrations are a distinct concern.

### The rule: each primitive is its own .gd file

No `utils.gd` mega-file. No `helpers.gd`. Each primitive gets a
file with the same name. If it's not big enough for its own file,
it's not big enough to be a primitive.

### The rule: co-located tests

Each `math/nsc9.gd` has its `math/test_nsc9.gd` next to it. Not in
`game/tests/`. The exception is the islands POC test which
lives in `game/tests/` because it's a cross-cutting integration
test, not a primitive test.

### The rule: no autoload, no GameManager dependency

A primitive cannot `extends Node` unless it really needs scene
behavior. It cannot reference GameManager, EventBus, or any other
autoload. It can take dependencies via constructor params or
export vars.

This is what makes primitives *liftable*. A primitive in
`labs/multi-iso/math/nsc9.gd` should be able to copy-paste into a
standalone GDScript project and work.

### The rule: own README per directory (optional but recommended)

Each subdirectory can have a README explaining what's in it and why.
A `math/README.md` explains the geometry primitives. A `srv/README.md`
explains the service building blocks. A `db/README.md` explains
the database layer.

---

## How services consume primitives

Existing autoloads and services in `core/autoload/` and
`core/services/` should consume primitives, not reimplement them.

Examples (after the relevant sessions):

```gdscript
# core/services/orchestrator.gd (uses futures)
extends Node

const MarkovChain = preload("res://labs/multi-iso/srv/markov.gd")
const CompositeTable = preload("res://labs/multi-iso/srv/composite_table.gd")
const StateTree = preload("res://labs/multi-iso/kv/state_tree.gd")

var predictor: MarkovChain
var intersections: CompositeTable
var state: StateTree

func _ready() -> void:
    predictor = MarkovChain.new()
    intersections = CompositeTable.new(max_size=1000)
    state = StateTree.new()
```

The orchestrator is a coordinator that USES the primitives. It
doesn't contain the Markov logic, the LRU logic, or the tree
diffing logic. Those are in `labs/multi-iso/`.

This is the user's "everyone on the same page" principle. The
orchestrator is short and obvious. The primitives are isolated
and testable. The relationship is one-directional: services
depend on primitives, not the other way around.

---

## The frame extraction

When the multi-iso orchestrator is ready to be extracted as a
separate project (alongside vant), the contents of
`labs/multi-iso/` are the entire API surface.

Concretely:

```
# Old structure (in-tree)
labs/multi-iso/                # in-tree
game/core/services/       # in-tree
game/core/autoload/       # in-tree

# New structure (after extraction)
game/                     # game (no labs/)
multi-iso-frame/               # new repo
  ├── core/
  │   ├── math/                # was labs/multi-iso/math/
  │   ├── kv/
  │   ├── srv/
  │   ├── db/
  │   └── README.md
  ├── tests/                   # primitive tests
  └── docs/
multi-iso-frame-game/          # example game using the frame (was Synmergia)
  └── core/services/orchestrator.gd
```

The frame is everything in `labs/multi-iso/`. The example game
(Synmergia) is a consumer of the frame.

This is the "could pioneer" outcome. Others can build their own
MMOs on top of the frame.

---

## The concrete mapping: which session's work goes where

Sessions from the migration plan, mapped to their `futures/` homes:

| Session | Work | Lands in |
|---------|------|----------|
| A-2 | UIPanel → islands | `game/ui/` (existing) |
| A-3 | State tree | `labs/multi-iso/kv/state_tree.gd` |
| A-4 | Save games as content-hashed trees | `labs/multi-iso/kv/save_service.gd` (or new `srv/`) |
| A-5 | Item template content-hash | `labs/multi-iso/srv/item_template.gd` |
| A-6 | Asset addressing | `labs/multi-iso/kv/asset_address.gd` |
| A-7 | Build pipeline | `tools/build.sh` (out of tree) |
| B-1 | Math primitives | `labs/multi-iso/math/{nsc9,icosahedral,quasicrystal}.gd` |
| B-2 | Single-axis orchestrator | `labs/multi-iso/srv/axis.gd` |
| B-3 | Multi-axis intersection | `labs/multi-iso/srv/composite_table.gd` |
| B-4 | NSC-9 axis reservation | `labs/multi-iso/srv/axis_registry.gd` |
| B-5 | Orchestrator + frame glue | `core/services/orchestrator.gd` + `labs/multi-iso/README.md` |
| B-6 | Materialized intersection tables | `labs/multi-iso/srv/composite_table.gd` (extension) |
| B-7 | LOD pyramid | `labs/multi-iso/srv/lod_manager.gd` |
| B-8 | Predictive prefetch | `labs/multi-iso/srv/predictor.gd` + `markov.gd` |
| B-9 | Performance budget | docs |
| B-10 | Frame extraction | new repo |

Most of the work lands in `labs/multi-iso/`. The services directory
shrinks. The autoloads directory stays (it's about the runtime
singleton pattern), but its members become thin wrappers around
`labs/multi-iso/` primitives.

---

## The migration path (for existing code)

The existing Synmergia code (30+ autoloads, 30+ services) already
has some primitives embedded. We don't need to refactor them all
now. But going forward:

1. **New code**: write primitives in `labs/multi-iso/`, use them
   from services. Always.
2. **Existing services that need new logic**: extract the new
   logic to `labs/multi-iso/`, then call it from the service.
3. **Existing autoloads that have grown large**: identify the
   primitive inside, extract it, leave the autoload as a thin
   wrapper.

Don't refactor for the sake of refactoring. The principle is
applied to NEW work and to cases where it's natural. The
existing autoload cascade fix (the 22-cascade) is independent of
this and uses the shim approach.

---

## The "same page" benefit

When a developer (or future agent) opens the project, they can
read the system in this order:

1. `labs/multi-iso/README.md` — what primitives exist
2. `labs/multi-iso/math/` — what math is used
3. `labs/multi-iso/kv/` — what data structures exist
4. `labs/multi-iso/srv/` — what service building blocks exist
5. `labs/multi-iso/db/` — what database layer exists
6. `core/services/` — how services use the primitives
7. `core/autoload/` — how the runtime wires it together

Each layer depends only on the layers below. Each layer is
testable in isolation. The relationship is obvious from the
directory structure.

This is the "everyone on the same page" effect. The directory
structure is the documentation.

---

## What this doc is

A convention for organizing the new code. It doesn't refactor
existing code. It says: when you write new code, write primitives
in `labs/multi-iso/`, use them from services. The frame extraction
later will lift `labs/multi-iso/` into its own project.

This is the "raw-dog" organization. No framework, no abstraction
layer. Just well-organized independent tools.

User's framing: "Then we will all be on the same page." The
directory IS the page.
