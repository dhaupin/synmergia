## PresolveProps - load + VALIDATE a prop presolve artifact and install it
## into TerrainGen (labs/prd-perf-bridges.md Facet 3, live consumer).
##
## The artifact (`game/data/presolve/props_<world>.txt`, emitted offline by
## `srv/julia-bridge/prop_presolve.jl`) carries every face's rock + boulder
## specs, so the frame skips the PCG32 derivation and a CLIENT can load the
## same artifact instead of re-deriving. Measured: 17.7x on the derive
## (labs/prd-perf-bridges.md Facet 3).
##
## SAFETY: an artifact is trusted only after it proves itself against the
## live law. `load_for` checks the seed + ruleset header, then re-derives a
## SAMPLE of faces analytically and compares counts + a direction tolerance.
## Any mismatch -> the artifact is rejected and TerrainGen keeps the
## analytic law (the artifact is an accelerator, never a new truth).
##
## This is the BATCH path (a committed artifact), NOT the HTTP sidecar --
## deliberate, because the sidecar's JSON/HTTP deps do not load here (see
## srv/julia-bridge/README.md). No autoload: call `load_for` from the boot
## seam that owns the world seed.
extends RefCounted

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

const DIR_TOL: float = 1e-5
const SCALE_TOL: float = 1e-4
const SAMPLE_FACES: Array = [0, 5, 13, 19]


## Load the artifact for `world_id`'s seed and install it into TerrainGen.
## Returns a small report: {"installed": bool, "reason": String,
## "rocks": int, "boulders": int, "faces": int}.
static func load_for(world_seed: PackedByteArray, world_id: String) -> Dictionary:
	var path: String = "res://data/presolve/props_%s.txt" % world_id
	if not FileAccess.file_exists(path):
		return {"installed": false, "reason": "no artifact at %s" % path,
			"rocks": 0, "boulders": 0, "faces": 0}

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"installed": false, "reason": "open failed: %s" % path,
			"rocks": 0, "boulders": 0, "faces": 0}
	var text: String = f.get_as_text()
	f.close()

	var parsed: Dictionary = _parse(text)
	if not parsed.get("ok", false):
		return {"installed": false, "reason": parsed.get("reason", "parse error"),
			"rocks": 0, "boulders": 0, "faces": 0}

	if parsed["seed_hex"] != world_seed.hex_encode():
		return {"installed": false, "reason": "seed mismatch (artifact %s)" % parsed["seed_hex"],
			"rocks": 0, "boulders": 0, "faces": 0}
	if parsed["ruleset"] != TerrainGen.RULESET_VERSION:
		return {"installed": false, "reason": "ruleset mismatch (artifact %s)" % parsed["ruleset"],
			"rocks": 0, "boulders": 0, "faces": 0}

	# Prove the artifact against the live law on a sample of faces. The live
	# law is read with the artifact UNINSTALLED (so we compare real derive to
	# artifact, never artifact to itself).
	var rocks: Dictionary = parsed["rocks"]
	var boulders: Dictionary = parsed["boulders"]
	TerrainGen.uninstall_presolve()
	for face in SAMPLE_FACES:
		if not rocks.has(face) or not boulders.has(face):
			return {"installed": false, "reason": "artifact missing face %d" % face,
				"rocks": 0, "boulders": 0, "faces": 0}
		var live_r: Array = TerrainGen.rock_specs(world_seed, face)
		if live_r.size() != (rocks[face] as Array).size():
			return {"installed": false, "reason": "rock count drift on face %d (%d vs %d)"
				% [face, live_r.size(), (rocks[face] as Array).size()],
				"rocks": 0, "boulders": 0, "faces": 0}
		for i in range(live_r.size()):
			var a = live_r[i]
			var b = (rocks[face] as Array)[i]
			if a.dir.distance_to(b.dir) > DIR_TOL or absf(a.scale - b.scale) > SCALE_TOL \
					or absf(a.yaw - b.yaw) > SCALE_TOL:
				return {"installed": false, "reason": "rock spec drift on face %d #%d" % [face, i],
					"rocks": 0, "boulders": 0, "faces": 0}
		var live_b: Array = TerrainGen.boulder_specs(world_seed, face)
		if live_b.size() != (boulders[face] as Array).size():
			return {"installed": false, "reason": "boulder count drift on face %d" % face,
				"rocks": 0, "boulders": 0, "faces": 0}
		for i in range(live_b.size()):
			var a2 = live_b[i]
			var b2 = (boulders[face] as Array)[i]
			if a2.dir.distance_to(b2.dir) > DIR_TOL or absf(a2.radius - b2.radius) > SCALE_TOL \
					or absf(a2.yaw - b2.yaw) > SCALE_TOL:
				return {"installed": false, "reason": "boulder spec drift on face %d #%d" % [face, i],
					"rocks": 0, "boulders": 0, "faces": 0}

	TerrainGen.install_presolve(rocks, boulders, world_seed)
	return {"installed": true, "reason": "validated", "rocks": parsed["total_r"],
		"boulders": parsed["total_b"], "faces": rocks.size()}


## Parse the artifact text into typed spec maps. Pure; no TerrainGen touch.
static func _parse(text: String) -> Dictionary:
	var lines: PackedStringArray = text.split("\n", false)
	if lines.size() < 4 or not lines[0].begins_with("SYNMERGIA PRESOLVE props"):
		return {"ok": false, "reason": "bad header"}
	var seed_hex: String = ""
	var ruleset: String = ""
	var rocks: Dictionary = {}
	var boulders: Dictionary = {}
	var cur_face: int = -1
	var total_r: int = 0
	var total_b: int = 0
	var saw_end: bool = false

	for raw in lines:
		var line: String = raw.strip_edges()
		if line.is_empty():
			continue
		var parts: PackedStringArray = line.split(" ", false)
		match parts[0]:
			"SEED":
				seed_hex = parts[1]
			"RULESET":
				ruleset = parts[1]
			"FACES":
				pass
			"FACE":
				cur_face = int(parts[1])
				rocks[cur_face] = []
				boulders[cur_face] = []
			"R":
				if cur_face < 0:
					return {"ok": false, "reason": "R before FACE"}
				var rs := TerrainGen.RockSpec.new()
				rs.dir = Vector3(float(parts[1]), float(parts[2]), float(parts[3])).normalized()
				rs.scale = float(parts[4])
				rs.yaw = float(parts[5])
				(rocks[cur_face] as Array).append(rs)
			"B":
				if cur_face < 0:
					return {"ok": false, "reason": "B before FACE"}
				var bs := TerrainGen.BoulderSpec.new()
				bs.dir = Vector3(float(parts[1]), float(parts[2]), float(parts[3])).normalized()
				bs.radius = float(parts[4])
				bs.yaw = float(parts[5])
				(boulders[cur_face] as Array).append(bs)
			"END":
				total_r = int(parts[1])
				total_b = int(parts[2])
				saw_end = true
			_:
				pass

	if seed_hex.is_empty() or ruleset.is_empty():
		return {"ok": false, "reason": "missing seed/ruleset header"}
	if not saw_end:
		return {"ok": false, "reason": "missing END"}
	if rocks.is_empty():
		return {"ok": false, "reason": "no faces"}
	return {"ok": true, "seed_hex": seed_hex, "ruleset": ruleset,
		"rocks": rocks, "boulders": boulders, "total_r": total_r, "total_b": total_b}
