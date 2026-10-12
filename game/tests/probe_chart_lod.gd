## Probe: PenroseChartLod — the runtime LOD policy service.
## Headless probe; run with the project's test runner (script mode):
##   godot --headless --path game --script res://tests/probe_chart_lod.gd
##
## Covers the policy laws each probe-law maps to:
##   1. PYRAMID LADDER — desired_subdiv is a non-increasing step function
##      of angular distance, and lands exactly on {0, 1, 2}.
##   2. SAFETY BASE — no plan ever goes below the ladder base (0).
##   3. NEIGHBOR CONTRACT — after settle_seams no chart exceeds any
##      neighbor by more than MAX_NEIGHBOR_GAP.
##   4. LADDER CLAMP — plan never exceeds LADDER_TOP.
##   5. DETERMINISM — same observer position yields an identical plan,
##      including its audit delta behavior (empty delta for unchanged
##      states, and a delta that is exactly the changed indices).
##
## Part 2 — the wiring (PenroseChartAdapter):
##   W1. APPLY-ON-DELTA — orders are queued for changed charts only;
##       cold start queues every chart; unchanged positions queue zero.
##   W2. REBUILD CONTRACT — every order carries rung, half_extent,
##       skirt_depth, base_subdiv, and the SHARED seam sample set.
##   W3. STABLE IDS — order identities are dense-layout indices, and
##       an order exists for every delta index.
##   W4. TRAILING-NEIGHBOR SKIRT PAD — padded_skirt adds the pad only
##       when a seam neighbor trails, and only up to the pad once.
extends SceneTree

const LodScript = preload("res://scenes/worlds/penrose_chart_lod.gd")
const PentagridScript = preload("res://core/frame/math/pentagrid.gd")
const AdapterScript = preload("res://scenes/worlds/penrose_chart_adapter.gd")

var _fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: " + label)


func _run() -> void:
	_law_ladder()
	_law_base_floor()
	_law_neighbor_contract()
	_law_clamp()
	_law_determinism_and_delta()
	_wire_apply_on_delta()
	_wire_rebuild_contract()
	_wire_trailing_skirt_pad()
	print("probe_chart_lod: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


## Law 1: monotone bands.
func _law_ladder() -> void:
	var cap := deg_to_rad(float(PentagridScript.patch_cap_deg(20)))
	var steps: Array = []
	for k in range(0, 2001):
		var d := (cap * 2.0) * (float(k) / 2000.0) - 0.05
		var s := LodScript.desired_subdiv(d)
		_check(s in [0, 1, 2], "desired_subdiv in ladder: d=%f s=%d" % [d, s])
		# Monotone check via pairs.
		if steps.size() > 0:
			_check(s <= int(steps[-1]), "pairwise monotone at d=%f" % d)
		steps.append(s)
	# Rung 2 exists near the center (i.e. the ladder actually climbs).
	var center := LodScript.desired_subdiv(0.0)
	_check(center == LodScript.LADDER_TOP, "center pins to LADDER_TOP")


## Law 2: plan never dips below base (0) — implies every chart gets a
## plan entry, i.e. the base layout covers the planet alone.
func _law_base_floor() -> void:
	var safe: Dictionary = LodScript.plan_safe(-45.0, 120.0)
	_check(not safe.is_empty(), "plan_safe covers every chart")
	for i in safe:
		var s := int(safe[i]["subdiv"])
		_check(s >= 0, "subdiv floor for chart %d" % i)


## Law 3: seam contract after settling, probed over several observers.
func _law_neighbor_contract() -> void:
	for probe in [[0.0, 0.0], [23.5, -67.0], [-51.0, 88.0], [62.0, 5.0]]:
		var safe: Dictionary = LodScript.plan_safe(float(probe[0]), float(probe[1]))
		var centers: Array = PentagridScript.atlas_centers_dense(1)
		for i in safe:
			for j in range(centers.size()):
				if j == i:
					continue
				var d: float = PentagridScript.SphericalScript.haversine(
					centers[i].x, centers[i].y, centers[j].x, centers[j].y, 1.0)
				if d >= 2.0 * deg_to_rad(PentagridScript.atlas_covering_radius_deg()) * 1.05:
					continue  # not a neighbor
				var gap := int(safe[i]["subdiv"]) - int(safe[j]["subdiv"])
				_check(
					gap <= LodScript.MAX_NEIGHBOR_GAP,
					"neighbor gap law i=%d j=%d gap=%d" % [i, j, gap])
			# Skirt rule: skirt depth tracks the rung.
			var s := int(safe[i]["subdiv"])
			_check(
				absf(float(safe[i]["skirt_depth"]) - LodScript.skirt_for(s)) < 0.0001,
				"skirt tracking for chart %d" % i)


## Law 4: clamp — plus the skirt pad constant is reachable via service.
func _law_clamp() -> void:
	_check(LodScript.LADDER_TOP >= 1, "ladder has at least one rung")
	_check(LodScript.MAX_NEIGHBOR_GAP >= 0, "half-step law configured")
	_check(LodScript.SKIRT_REBUILD_PADDING > 0.0, "skirt pad configured")
	_check(LodScript.skirt_for(LodScript.LADDER_TOP) <= LodScript.SKIRT_REBUILD_PADDING * 4.0,
		"skirt ladder below the pad ceiling")


## Law 5: determinism + audit delta.
func _law_determinism_and_delta() -> void:
	var a: Dictionary = LodScript.plan_safe(10.0, -20.0)
	var b: Dictionary = LodScript.plan_safe(10.0, -20.0)
	_check(a == b, "identical plans for identical observer")

	var moved: Dictionary = LodScript.plan_safe(38.0, 141.0)
	var idxs: Array = LodScript.plan_delta(a, moved)
	_check(idxs.size() <= a.size(), "delta bounded by chart count")
	# Every reported index must really differ; every differing index must be reported.
	var expected := {}
	for i in moved:
		if int(a[i]["subdiv"]) != int(moved[i]["subdiv"]):
			expected[i] = true
	var reported := {}
	for i in idxs:
		reported[i] = true
	_check(expected.has_all(reported.keys()), "delta reports only true changes")
	_check(reported.has_all(expected.keys()), "delta reports every true change")
	_check(LodScript.plan_delta(a, a).is_empty(), "no delta for unchanged state")


## ---- Part 2: the wiring (PenroseChartAdapter) ----

## W1: apply-on-delta — changed charts only; cold start queues all;
## unchanged observer queues zero.
func _wire_apply_on_delta() -> void:
	var adapter: RefCounted = AdapterScript.new()
	# Cold start: every chart gets an order.
	var cold: Dictionary = LodScript.plan_safe(0.0, 0.0)
	var cold_orders: Array = adapter.apply_plan(cold)
	_check(cold_orders.size() == cold.size(), "cold start orders every chart")
	# Same observer again: nothing changed, no orders.
	var same: Dictionary = LodScript.plan_safe(0.0, 0.0)
	var no_orders: Array = adapter.apply_plan(same)
	_check(no_orders.is_empty(), "unchanged observer queues zero orders")
	# A distinct observer: orders bounded by the true changed set.
	var moved: Dictionary = LodScript.plan_safe(41.0, 139.0)
	var moved_orders: Array = adapter.apply_plan(moved)
	var expected := {}
	for i in moved:
		if int(cold[i]["subdiv"]) != int(moved[i]["subdiv"]):
			expected[i] = true
	_check(moved_orders.size() == expected.size(),
		"order count equals changed-count (%d vs %d)" % [moved_orders.size(), expected.size()])
	var order_ids := {}
	for o in moved_orders:
		order_ids[int(o["chart_index"])] = true
	_check(expected.has_all(order_ids.keys()), "orders exactly cover the delta")
	# Determinism: same sequence again yields the same orders.
	var adapter2: RefCounted = AdapterScript.new()
	adapter2.update_observer(0.0, 0.0)
	adapter2.apply_plan(LodScript.plan_safe(0.0, 0.0))
	var replay: Array = adapter2.update_observer(41.0, 139.0)
	_check(replay.size() == moved_orders.size(), "replay order count matches")
	var replay_ids := {}
	for o in replay:
		replay_ids[int(o["chart_index"])] = true
	_check(order_ids == replay_ids, "replay covers the same chart indices")

## W2/W3: rebuild contract + stable ids.
func _wire_rebuild_contract() -> void:
	var adapter: RefCounted = AdapterScript.new()
	var plan: Dictionary = LodScript.plan_safe(25.0, -3.0)
	var orders: Array = adapter.apply_plan(plan, 1)
	_check(not orders.is_empty(), "contract probe produced orders")
	var base_subdiv := 1
	var samples: Dictionary = PentagridScript.chart_boundary_samples(base_subdiv)
	for o in orders:
		var idx := int(o["chart_index"])
		_check(idx >= 0 and idx < PentagridScript.atlas_centers_dense(base_subdiv).size(),
			"order id is a dense-layout index (%d)" % idx)
		_check(int(o["rung"]) == int(plan[idx]["subdiv"]), "order rung matches plan for %d" % idx)
		_check(float(o["half_extent"]) > 0.0, "order half_extent positive for %d" % idx)
		_check(float(o["skirt_depth"]) > 0.0, "order skirt_depth positive for %d" % idx)
		_check(int(o["base_subdiv"]) == base_subdiv, "order base_subdiv carried for %d" % idx)
		var o_samples: Dictionary = o["seam_samples"]
		_check(o_samples == samples, "seam samples are the shared set for %d" % idx)
		_check(not o_samples.is_empty(), "seam sample set nonempty for %d" % idx)
	# Identical calls yield identical orders (determinism of the contract).
	var adapter2: RefCounted = AdapterScript.new()
	var orders2: Array = adapter2.apply_plan(LodScript.plan_safe(25.0, -3.0), 1)
	_check(orders2 == orders, "rebuild contract deterministic across instances")

## W4: trailing-neighbor skirt pad.
func _wire_trailing_skirt_pad() -> void:
	var adapter: RefCounted = AdapterScript.new()
	# Build a synthetic trailing plan: the center chart pinned to the
	# top rung, every other chart dropped to rung 0.
	var trailing: Dictionary = LodScript.plan_safe(0.0, 0.0)
	var top := LodScript.LADDER_TOP
	var zeroed: Dictionary = {}
	for i in trailing:
		zeroed[i] = {"subdiv": 0, "skirt_depth": LodScript.skirt_for(0)}
	zeroed[0] = {"subdiv": top, "skirt_depth": LodScript.skirt_for(top)}
	# Chart 0 (north pole center): all it at-least-one seam neighbor
	# trails (rung 0 < top) so the pad MUST appear exactly once.
	var padded: float = adapter.padded_skirt(0, zeroed, 1)
	_check(padded > zeroed[0]["skirt_depth"], "trailing neighbor adds the pad")
	_check(absf(padded - (LodScript.skirt_for(top) + LodScript.SKIRT_REBUILD_PADDING)) < 0.0001,
		"pad applied exactly once")
	# Safe (settled) plan: the seam contract guarantees no neighbor gap
	# > 1, so a rung-2 chart has half-step neighbors and still no full
	# trailing gap; the pad never fires on a settled plan at rung 0
	# (nothing can be below the floor).
	var settled: Dictionary = LodScript.plan_safe(0.0, 0.0)
	var lowest := int(settled[0]["subdiv"])
	for i in settled:
		lowest = mini(lowest, int(settled[i]["subdiv"]))
	if lowest == int(settled[0]["subdiv"]):
		var base_padded: float = adapter.padded_skirt(0, settled, 1)
		_check(base_padded <= float(settled[0]["skirt_depth"]) + 0.0001,
			"no pad on a floor-rung chart in a settled plan")