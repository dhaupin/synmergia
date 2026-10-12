## PenroseChartLod — the runtime LOD policy for the chart atlas (the
## rendering-engine heartbeat decision the frame layer left open).
##
## The frame layer (pentagrid.gd) delivers INDEX-STABLE densification
## (atlas_centers_dense), shared seam samples (chart_boundary_samples),
## skirts (skirt_strip) and the adjacency table (chart_neighbors).
## This service owns the POLICY: when a player gets close, a chart
## climbs a subdivision ladder; when they leave, it descends. The
## policy's job is to make those moves safe for the seams.
##
## The plan is a pure function of player position — deterministic,
## replayable, and auditable (the world's anticheat story needs the
## plan to be a pure function of state, not of wall-clock or RNG).
## The renderer consumes the plan's deltas; nothing here touches Nodes
## or the scene tree (the service is data + decisions).
##
## Policy laws, each probed in game/tests/probe_chart_lod.gd:
##   1. PYRAMID LADDER: desired subdivision is a monotone function of
##      angular distance to the chart's center (closer = denser);
##      bands are annuli of the form [cap/n, cap/(n-1)).
##   2. SAFETY BASE: subdiv 0 is the always-provided floor (the base
##	    12-center layout covers the whole planet alone); no plan
##	    ever takes a chart BELOW the ladder's base.
##   3. NEIGHBOR CONTRACT: a chart's chosen subdiv may exceed ANY
##	    neighbor's by at most half the ladder (the "half-step" law):
##	    seams between two charts at very different densities are
##	    covered by the shared samples + skirt strips at any density,
##	    but a full-ladder jump means very dense-to-very-sparse rims
##	    where even skirts visibly sag — the half-step bounds it.
##   4. LADDER CLAMP: the plan clamps to the ladder's top rung (the
##      maximum densification the data layer supports per tick, 2).
##   5. DETERMINISM: the same player position yields the same plan
##      (pure function; the audit record is the world's replay log
##      for this subsystem).
extends RefCounted
class_name PenroseChartLod

const PentagridScript = preload("res://core/frame/math/pentagrid.gd")

## Ladder top: the densest subdivision the tick-time budget allows a
## chart to occupy (the frame layer's atlas_centers_dense(2) call
## costs ~4x the base layout; the renderer's per-chart budget shows
## its own number). The policy refuses to plan beyond this.
const LADDER_TOP: int = 2

## Half-step law: the maximum ladder gap between bordering charts.
const MAX_NEIGHBOR_GAP: int = 1

## Skirt rule: whenever a chart's rim backs an empty space (a neighbor
## is DELAYED from its rebuild), the plan pads that chart's skirt
## depth so the crack never shows a z-fight. Exposed as a number of
## tiling units, the same unit skirt_strip takes.
const SKIRT_REBUILD_PADDING: float = 0.75


## The desired subdivision for ONE chart given the observer's angular
## distance (radians on the unit sphere): bands tighten toward the
## center. Band edges: LADDER_TOP sub-rungs between the covering
## radius (full density sphere) and the outer cap.
static func desired_subdiv(angular_dist_rad: float) -> int:
	if angular_dist_rad < 0.0:
		angular_dist_rad = 0.0
	var full_cap: float = deg_to_rad(PentagridScript.patch_cap_deg(20))
	# The ladder: rung n takes [full_cap * (4-n)/4, full_cap * (5-n)/4)
	# so rung LADDER_TOP is the closest band and rung 0 is the whole
	# cap out to the projection limit.
	var rungs: int = LADDER_TOP + 1
	# Band k (innermost first): [full_cap*k/rungs, full_cap*(k+1)/rungs)
	# maps to rung rungs-1-k, so rung LADDER_TOP hugs the center and rung
	# 0 spans the outermost band (plus everything past the cap).
	for k in range(rungs):
		var outer: float = full_cap * float(k + 1) / float(rungs)
		if angular_dist_rad < outer:
			return rungs - 1 - k
	return 0


## The plan for all charts: for each center of the chosen density
## layout, desired chart-level subdiv given the observer (lat, lon,
## degrees). Deterministic pure function.
static func plan(observer_lat: float, observer_lon: float, base_subdiv: int = 1) -> Dictionary:
	var centers: Array = PentagridScript.atlas_centers_dense(base_subdiv)
	var out: Dictionary = {}
	for i in range(centers.size()):
		var c: Vector2 = centers[i]
		var d: float = PentagridScript.SphericalScript.haversine(observer_lat, observer_lon, c.x, c.y, 1.0)
		out[i] = desired_subdiv(d)
	return out


## Seam SAFETY pass over a plan: no chart's plan may exceed any
## neighbor's by more than MAX_NEIGHBOR_GAP. Violators step down.
## Returns the corrected plan (a NEW dict; the input is untouched).
static func settle_seams(plan_in: Dictionary, base_subdiv: int = 1) -> Dictionary:
	var corrected: Dictionary = plan_in.duplicate()
	var centers: Array = PentagridScript.atlas_centers_dense(base_subdiv)
	# Descending pass: high charts step down until the neighbor law
	# holds everywhere (iterate until fixed point; the ladder is 3
	# rungs so at most LADDER_TOP iterations).
	for _pass in range(PenroseChartLod.LADDER_TOP + 1):
		var changed := false
		for i in range(centers.size()):
			var mine: int = int(corrected.get(i, 0))
			for j in range(centers.size()):
				if j == i:
					continue
				var d: float = PentagridScript.SphericalScript.haversine(
					centers[i].x, centers[i].y, centers[j].x, centers[j].y, 1.0)
				if d >= 2.0 * deg_to_rad(PentagridScript.atlas_covering_radius_deg()) * 1.05:
					continue  # not a neighbor
				var theirs: int = int(corrected.get(j, 0))
				if mine - theirs > PenroseChartLod.MAX_NEIGHBOR_GAP:
					corrected[i] = mine - PenroseChartLod.MAX_NEIGHBOR_GAP
					mine = int(corrected[i])
					changed = true
		if not changed:
			break
	return corrected


## The full plan with seam safety applied: the entry point the world
## tick calls. Legend: {chart_index: {subdiv, skirt_depth}}.
static func plan_safe(observer_lat: float, observer_lon: float, base_subdiv: int = 1) -> Dictionary:
	var raw: Dictionary = plan(observer_lat, observer_lon, base_subdiv)
	var settled: Dictionary = settle_seams(raw, base_subdiv)
	var out: Dictionary = {}
	for i in settled:
		var s: int = int(settled[i])
		out[i] = {"subdiv": s, "skirt_depth": skirt_for(s)}
	return out


## Skirt depth per rung: denser charts expose longer rims (more tiles
## to bridge), so skirts grow with density. The world tick feeds
## these directly into skirt_strip.
static func skirt_for(subdiv: int) -> float:
	return 0.25 + 0.25 * subdiv


## Audit record of one plan: the chart indices whose desired subdiv
## changed vs the previous plan (the renderer consumes only these —
## the frames' diff, not the whole map). Takes the SETTLED shape
## ({index: {subdiv, skirt_depth}}) from plan_safe on both sides.
static func plan_delta(prev: Dictionary, next: Dictionary) -> Array:
	var out: Array = []
	for i in next:
		var prev_s: int = int(prev[i]["subdiv"]) if prev.has(i) else -1
		if prev_s != int(next[i]["subdiv"]):
			out.append(i)
	return out
