## PenroseChartAdapter — the wiring the LOD policy's turn-6 record left
## open: the runtime layer between PenroseChartLod's emitted plan deltas
## and the frame layer's rebuild primitives (atlas_centers_dense +
## skirt_strip). One object owns the per-chart rung state; callers feed
## it observer positions and it returns the DELTA work orders.
##
## Laws, each probed in game/tests/probe_chart_lod.gd (Part 2):
##   W1. APPLY-ON-DELTA: apply_plan() only queues work for charts whose
##       subdiv actually changed (plan_delta contract). Cold start
##       (last_plan empty) queues every chart — the whole atlas first
##       ship. Returns the queued work orders, not the whole map.
##   W2. REBUILD CONTRACT: each order carries the data-layer rebuild
##       inputs in one dict: rung, patch half-extent, skirt depth,
##       base subdiv for atlas_centers_dense, and the shared seam
##       sample set (chart_boundary_samples) — identical for both
##       seam partners at the same density.
##   W3. STABLE IDS: chart identity is the dense-layout INDEX
##       (index-stable across densities per the frame layer's law);
##       orders and skirt references carry the index, never a center
##       position.
##   W4. TRAILING-NEIGHBOR SKIRT PAD: padded_skirt() adds the policy's
##       SKIRT_REBUILD_PADDING when a seam neighbor is still on a
##       LOWER rung — the pad bridges the rebuild gap so the seam
##       never shows a crack while the neighbor catches up.
##
## Determinism: pure state machine over plans (no RNG, no wall clock).
## The same sequence of observer positions yields the same work-order
## sequence — replayable like the policy itself.
extends RefCounted
class_name PenroseChartAdapter

const LodScript = preload("res://scenes/worlds/penrose_chart_lod.gd")
const PentagridScript = preload("res://core/frame/math/pentagrid.gd")

## Region growth per ladder rung (tiling units of patch half-extent):
## rung 0 = 4.0, rung 1 = 6.0, rung 2 = 8.0. Denser rung => larger
## sampled region so densification dominates truncation.
const RUNG_HALF_EXTENT: Array[float] = [4.0, 6.0, 8.0]

## Last applied plan: chart_index -> {subdiv, skirt_depth}.
var last_plan: Dictionary = {}

## Work orders queued by the last apply_plan()/update_observer() call.
var last_orders: Array = []


## Take the settled plan and turn WHAT CHANGED into work orders.
## plan: {index: {subdiv, skirt_depth}} (PenroseChartLod.plan_safe).
## Returns an Array of order dicts:
##   {chart_index, rung, half_extent, skirt_depth, base_subdiv,
##    seam_samples}
## where seam_samples is the SHARED chart_boundary_samples(base_subdiv)
## set — identical for any seam partner at the same density.
func apply_plan(plan: Dictionary, base_subdiv: int = 1) -> Array:
	var delta: Array = []
	if last_plan.is_empty():
		for i in plan:
			delta.append(i)
	else:
		delta = LodScript.plan_delta(last_plan, plan)
	var orders: Array = []
	var samples: Dictionary = PentagridScript.chart_boundary_samples(base_subdiv)
	for i in delta:
		var idx := int(i)
		var entry: Dictionary = plan[i]
		var rung := int(entry["subdiv"])
		var skirt := float(entry["skirt_depth"])
		var extent: float = RUNG_HALF_EXTENT[clampi(rung, 0, RUNG_HALF_EXTENT.size() - 1)]
		orders.append({
			"chart_index": idx,
			"rung": rung,
			"half_extent": extent,
			"skirt_depth": skirt,
			"base_subdiv": base_subdiv,
			"seam_samples": samples,
		})
	last_plan = plan.duplicate()
	last_orders = orders
	return orders


## Convenience: one call from a player position (degrees). Pure
## policy -> plan -> orders chain; same laws as the parts upstream.
func update_observer(lat: float, lon: float, base_subdiv: int = 1) -> Array:
	var plan: Dictionary = LodScript.plan_safe(lat, lon, base_subdiv)
	return apply_plan(plan, base_subdiv)


## The skirt depth a chart's rim should use RIGHT NOW: on top of the
## plan's skirt_depth, SKIRT_REBUILD_PADDING is added when at least
## one seam neighbor is still BELOW this chart's rung (its rebuild
## trails). The result feeds skirt_strip directly, in its tiling
## units.
func padded_skirt(chart_index: int, plan: Dictionary, base_subdiv: int = 1) -> float:
	var rung := int(plan[chart_index]["subdiv"])
	var depth := float(plan[chart_index]["skirt_depth"])
	var centers: Array = PentagridScript.atlas_centers_dense(base_subdiv)
	var covering := deg_to_rad(PentagridScript.atlas_covering_radius_deg())
	var me: Vector2 = centers[chart_index]
	for j in range(centers.size()):
		if j == chart_index:
			continue
		var d: float = PentagridScript.SphericalScript.haversine(
			me.x, me.y, centers[j].x, centers[j].y, 1.0)
		if d >= 2.0 * covering * 1.05:
			continue  # not a seam neighbor at this density
		if int(plan[j]["subdiv"]) < rung:
			# The neighbor trails; pad my rim so the crack cannot show.
			depth += LodScript.SKIRT_REBUILD_PADDING
			break
	return depth
