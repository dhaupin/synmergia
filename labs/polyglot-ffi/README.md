# labs/polyglot-ffi/ — Polyglot FFI (cherry-picked from vant)

**The plan:** Lift the **Polyglot FFI** pattern from
[vant `lib/compute.js`](https://github.com/dhaupin/vant/blob/axolotl/lib/compute.js)
and adapt it for GDScript. The result: a registry of language
connectors that the frame can call for vector math, ML,
sandboxed eval, or anything that benefits from a non-GDScript
runtime.

---

## What vant does (the source pattern)

Vant's `lib/compute.js` is a **polyglot FFI** that auto-discovers
language connectors dropped in `lib/connectors/`:

```js
// vant/lib/compute.js
const langConnectors = ['python', 'julia', 'rust', 'node', 'ruby', 'go', 'php'];
// on startup, scan connectors/, require each one, register by lang

// Usage:
const result = await compute.invoke('numpy.linalg.eig', { matrix: [[1,2],[3,4]] }, 'python');
const result2 = await compute.eval('println(2 + 2)', { lang: 'julia' });
const status = compute.status();  // what's available

// Shortcuts:
const r3 = await compute.julia('LinearAlgebra.eig', [[1,2],[3,4]]);
```

The Julia connector is 76 lines. It extends `BaseConnector`:

```js
// vant/lib/connectors/julia.js
class JuliaConnector extends BaseConnector {
  getLang() { return 'julia'; }
  getCmd() { return this._options.julia || 'julia'; }
  getArgs(codeOrFile) { return ['-e', codeOrFile]; }
  async invoke(func, args) { ... }  // build code, execute
  async eval(code) { ... }           // raw code, execute
  async run(scriptPath, args) { ... } // spawn julia script.jl
  async ping() { ... }               // health check
}
```

The base class handles subprocess, timeouts, recursion guard,
event emission. Connectors just specify `getCmd` and `getArgs`.

## Why we want it

GDScript is great for game logic but slow for the hot path:

- **Spatial queries over 10K entities** — 50ms in GDScript, ~5ms in Julia
- **State tree SHA-256 over millions of nodes** — 200ms in GDScript, ~20ms in Julia
- **Intersection materialization (1000 hot combos)** — Julia is 10-50x
- **LOD batch operations** — Julia again
- **ML inference** — Python (PyTorch) or Julia (Flux.jl)

**The rule:** write game logic in GDScript. Write hot math in
the language that does it best. The polyglot FFI is the bridge.

## What this lab will contain

```
labs/polyglot-ffi/
├── README.md                       # this file
├── design.md                       # long-form design, code examples
├── compute.gd                      # main entry, autoloaded OR service
├── connectors/
│   ├── base_connector.gd           # abstract base
│   ├── julia_connector.gd          # Julia via OS.execute + StreamPeer
│   ├── python_connector.gd         # Python via OS.execute
│   ├── rust_connector.gd           # Rust via compiled binary
│   └── tests/
│       ├── test_base_connector.gd
│       ├── test_julia_connector.gd
│       └── test_python_connector.gd
├── julia-runtime/                  # the Julia-specific implementation
│   ├── README.md                   # design for Julia use cases
│   ├── scripts/                    # Julia code that runs server-side
│   │   ├── spatial_query.jl        # 10K entity range query
│   │   ├── state_hash.jl           # hash the state tree
│   │   ├── intersection.jl         # materialize intersection tables
│   │   └── lod_batch.jl            # batch promote/demote regions
│   └── Project.toml                # Julia package manifest
└── decision.md                     # "use Julia for X" use cases
```

## The GDScript adaptation

Vant's pattern is clean but JS-specific. The GDScript port:

```gdscript
# labs/polyglot-ffi/compute.gd
extends RefCounted

var _connectors: Dictionary = {}  # lang -> BaseConnector

func _init() -> void:
    _discover_connectors()

func _discover_connectors() -> void:
    var dir := DirAccess.open("res://labs/polyglot-ffi/connectors")
    if dir == null:
        push_warning("No polyglot connectors dir")
        return
    for file in dir.get_files():
        if not file.ends_with(".gd"):
            continue
        var name := file.get_basename()
        if name in ["base_connector", "compute"]:
            continue
        var script := load("res://labs/polyglot-ffi/connectors/" + file)
        if script == null:
            continue
        var instance = script.new()
        if not instance is BaseConnector:
            continue
        _connectors[instance.get_lang()] = instance

# Main API
func invoke(func_name: String, args: Dictionary, lang: String) -> Variant:
    return _connectors[lang].invoke(func_name, args)

func eval(code: String, lang: String, timeout: float = 30.0) -> Variant:
    return _connectors[lang].eval(code, timeout)

func run(script_path: String, args: Array, lang: String = "") -> Variant:
    var resolved_lang := lang if lang != "" else _detect_lang(script_path)
    return _connectors[resolved_lang].run(script_path, args)

func status() -> Dictionary:
    var result := {"name": "Polyglot FFI", "available": []}
    for lang in _connectors:
        result.available.append(lang)
    return result

# Shortcuts
func julia(func_name: String, args: Dictionary) -> Variant:
    return invoke(func_name, args, "julia")
```

```gdscript
# labs/polyglot-ffi/connectors/base_connector.gd
class_name BaseConnector
extends RefCounted

func get_lang() -> String:
    return ""

func get_cmd() -> String:
    return ""

func get_args(code_or_file: String) -> Array:
    return ["-e", code_or_file]

# Subclasses override these
func invoke(func_name: String, args: Dictionary) -> Variant:
    push_error("BaseConnector.invoke not implemented")
    return null

func eval(code: String, timeout: float = 30.0) -> Variant:
    var output := []
    var pid := OS.execute(get_cmd(), get_args(code), output, true, false)
    if pid != 0:
        return {"success": false, "output": output, "pid": pid}
    return {"success": true, "output": output}

func run(script_path: String, args: Array = []) -> Variant:
    var cmd_args := [script_path] + args
    var output := []
    var pid := OS.execute(get_cmd(), cmd_args, output, true, false)
    return {"success": pid == 0, "output": output, "pid": pid}

func ping() -> bool:
    var result := eval("println(1)", 5.0)
    return result.success
```

```gdscript
# labs/polyglot-ffi/connectors/julia_connector.gd
extends BaseConnector

func _init() -> void:
    pass  # nothing to set up

func get_lang() -> String:
    return "julia"

func get_cmd() -> String:
    return "julia"

func get_args(code_or_file: String) -> Array:
    # Julia: -e runs inline code, --project=path sets the project
    return ["--project=res://labs/polyglot-ffi/julia-runtime", "-e", code_or_file]

func _func_to_code(func_name: String, args: Dictionary) -> String:
    var parts := func_name.split(".")
    if parts.size() == 2:
        return """
using %s
result = %s(%s)
println(JSON.json(result))
""" % [parts[0], parts[1], JSON.stringify(args)]
    return """
result = %s(%s)
println(JSON.json(result))
""" % [func_name, JSON.stringify(args)]

func invoke(func_name: String, args: Dictionary) -> Variant:
    var code := _func_to_code(func_name, args)
    return eval(code)
```

That's the pattern. Each connector is ~50 lines of GDScript.

## When this is needed

- **Now:** speculative. POC doesn't have hot paths.
- **Phase 1 (State tree):** state hashing might be slow at
  scale. Julia early.
- **Phase 2 (Vertical Slice):** if 100+ NPCs cause frame drops.
- **Phase 4 (Track B, B-6/B-7/B-8):** materialized intersection
  tables, LOD batch ops, prediction. **First real use.**
- **Phase 6 (MMO Features):** ML inference for anti-cheat,
  prediction, analytics.

## Why GDScript for the connector, Julia for the math

The connector logic is small and rarely changes. It's I/O
orchestration. GDScript is fine for that.

The math is hot and rarely changes once written. Julia is
right for that.

The "lift-and-shift" principle: don't write hot math in the
language that's bad at math. Use the language that's good at
math, and have a small shim that bridges the two.

## Status

- [x] Design intent (cherry-picked from vant)
- [ ] `compute.gd` skeleton
- [ ] `base_connector.gd` skeleton
- [ ] `julia_connector.gd` skeleton
- [ ] `julia-runtime/Project.toml` and first script
- [ ] First benchmark: GDScript vs Julia for spatial query
- [ ] Decision: which paths move to Julia

## References

- [vant `lib/compute.js`](https://github.com/dhaupin/vant/blob/axolotl/lib/compute.js) — the source
- [vant `lib/connectors/julia.js`](https://github.com/dhaupin/vant/blob/axolotl/lib/connectors/julia.js) — the Julia connector
- [Julia language](https://julialang.org) — the runtime
- [Polyglot FFI](https://en.wikipedia.org/wiki/Foreign_function_interface) — the concept

## See also

- [`julia-runtime/README.md`](./julia-runtime/README.md) — the
  Julia-specific implementation plan
- [`../jolt-playground/README.md`](../jolt-playground/README.md) — the
  physics engine decision (sister lab, C++ tier)
