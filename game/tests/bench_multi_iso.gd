## Benchmark: the multi-iso orchestrator's core workload (register N
## entities across axes, then M multi-axis intersections), in GDScript.
## The Julia bridge runs the same workload (bench_orchestrator.jl); the
## two numbers are reported side by side in AGENTS.md.
##
## Run: godot --headless --path . --script res://tests/bench_multi_iso.gd
extends SceneTree

const N := 20000
const Q := 5000

var _axes := {"spatial": {}, "faction": {}, "social": {}}

func _spatial_at(vertex: int) -> Dictionary:
	var out := {}
	var axis := 1 + vertex
	for eid in _axes["spatial"]:
		if _axes["spatial"][eid] == axis:
			out[eid] = true
	return out

func _faction_eq(f: int) -> Dictionary:
	var out := {}
	var axis := 100 + f
	for eid in _axes["faction"]:
		if _axes["faction"][eid] == axis:
			out[eid] = true
	return out

func _intersect(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		if b.has(k):
			out[k] = true
	return out

func _init() -> void:
	# Deterministic arithmetic placement (identical in bench_orchestrator.jl)
	# so the query totals cross-check as a correctness signal.
	for i in N:
		var id := "e%d" % i
		_axes["spatial"][id] = 1 + (i % 12)
		_axes["faction"][id] = 100 + ((i * 7) % 100)
		_axes["social"][id] = 300 + ((i * 3) % 50)

	var t0 := Time.get_ticks_usec()
	var total := 0
	for q in Q:
		var v := q % 12
		var f := q % 100
		total += _intersect(_spatial_at(v), _faction_eq(f)).size()
	var t1 := Time.get_ticks_usec()

	print("GDSCRIPT_USEC ", t1 - t0, " total=", total, " n=", N, " q=", Q)
	quit(0)
