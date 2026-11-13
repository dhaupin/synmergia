## diag_detail_kinds - v9 world-dressing diagnostic. Boots the planet
## at the ordinary 20 km scale:
##   1) Built-chunk census: derive kinds (fresh) + built-node kinds.
##   2) FIELD-3 GROUND PASS (honest): every detail-kind node and every
##      tuft-batch instance whose radial over/under the analytic
##      surface is measured AGAINST planet_center (the world is
##      re-rooted near the player at planet scale, so the radius from
##      the world origin is not the ground radius).
##   3) THE TRAVEL CENSUS (GM travel): derive the detail tier across
##      ALL 20 base faces and bucket every SITE by ITS OWN band --
##      what a biome holds when a GM arrives, per site, not per face
##      center guess.
##
## This is a CENSUS diagnostic (no assertions). The clipmap's PropLayer
## is the sole flora path now (chunks named "PropChunk_%d").
## Run headless:   godot --headless --path . --script res://tests/diag_detail_kinds.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const RADIUS := 20000.0
const KIND_NAMES := {0: "tuft", 1: "flower", 2: "mushroom", 3: "mycelium", 4: "shell", 5: "wrack", 6: "cattail", 7: "bush", 8: "ore"}
const FacePatches = preload("res://core/frame/math/icosahedral_faces.gd")
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

var _globe: Node


func _init() -> void:
	call_deferred("_run")


func _over_run(provider, pc: Vector3, r: float, wp: Vector3, out: Dictionary, tag: String = "") -> void:
	var ndir: Vector3 = (wp - pc).normalized()
	var gh: float = float(provider.ground_height(ndir))
	var over: float = (wp - pc).length() - (r + gh)
	if over < -50.0 or over > 12.0:
		print("  BAD %s wp=%s |wp-pc|=%.1f gh=%.2f over=%.1f" % [tag, str(wp), (wp - pc).length(), gh, over])
	out["checked"] = int(out["checked"]) + 1
	out["worst_below"] = max(float(out["worst_below"]), -over)
	out["worst_above"] = max(float(out["worst_above"]), over)
	# THE SLOP HISTOGRAM: a systematic frame offset prints one big
	# far-bucket mass; relief slope prints a dense near-zero spread.
	var buck := "seat"
	if over < -50.0:
		buck = "deep"
	elif over < -8.0:
		buck = "sunk"
	elif over < -1.0:
		buck = "low"
	elif over <= 1.0:
		buck = "seat"
	elif over <= 3.0:
		buck = "proud"
	else:
		buck = "float"
	out[buck] = int(out.get(buck, 0)) + 1
	if over < -8.0 or over > 12.0:
		out["bad"] = int(out["bad"]) + 1


func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(10):
		await process_frame
	var clipmap = _globe.get("clipmap")
	var waited := 0
	while clipmap.pending_jobs() > 0 and waited < 300:
		await root.get_tree().physics_frame
		waited += 1
	for _i in range(20):
		await root.get_tree().physics_frame
	print("DIAG drained after=", waited, " tmsec=", Time.get_ticks_msec())

	var pl = clipmap.prop_layer()
	var provider = pl.provider if pl != null else null
	var pc: Vector3 = _globe.get("planet_center")
	var r: float = _globe.get("planet_radius")
	var holder_prefixes := ["Flower", "Bush", "Mushroom", "Cattail", "Ore", "Mycelium", "Tufts", "Scree", "Rock", "Boulder", "Tree"]
	var audit := {"checked": 0, "worst_below": -9999.0, "worst_above": -9999.0, "bad": 0}
	# --- 1) built chunks: fresh-derive kinds + built-node census -------
	var built: Array = pl._built.keys() if pl != null else []
	var depth: int = pl.chunk_depth if pl != null else PropChunk.DEFAULT_DEPTH
	for k in built:
		var chunk = pl._built.get(k)
		if chunk == null or not is_instance_valid(chunk):
			continue
		var fresh: Dictionary = pl.derive_fresh(k)
		var kinds := {}
		for rec in fresh.get("instances", []):
			if int(rec.get("family", -1)) == pl.FAMILY_DETAIL:
				var kn: String = str(KIND_NAMES.get(int(rec["kind"]), "?"))
				kinds[kn] = int(kinds.get(kn, 0)) + 1
		if not fresh.get("tufts", []).is_empty():
			kinds["tuft"] = int(kinds.get("tuft", 0)) + fresh["tufts"].size()
		var hh := {}
		for ch in chunk.get_children():
			var nm := String(ch.name)
			for pre in holder_prefixes:
				if nm.begins_with(pre):
					var mm: MultiMesh = ch.get("multimesh")
					var n: int = mm.instance_count if mm != null else 1
					hh[pre] = int(hh.get(pre, 0)) + n
					break
		print("chunk=%d DERIVE=%s BUILT=%s" % [k, str(kinds), str(hh)])
	# --- 2) FIELD-3 (honest, pc-relative) on the NEAR chunks ----------
	var viewer_dir: Vector3 = ((_globe.get("player") as Node3D).global_position - pc).normalized()
	for k in built:
		var chunk = pl._built.get(k)
		if chunk == null or not is_instance_valid(chunk):
			continue
		# Audit only the near chunks (real nodes): the interior the player stands on.
		var center: Vector3 = PropChunk.chunk_center_dir(k, depth)
		if center.angle_to(viewer_dir) * r > pl.NEAR_RADIUS_M:
			continue
		for ch in chunk.get_children():
			var nm: String = String(ch.name)
			var is_det := false
			for pre in ["Flower", "Bush", "Mushroom", "Cattail", "Mycelium", "Ore"]:
				if nm.begins_with(pre):
					is_det = true
					break
			if is_det:
				_over_run(provider, pc, r, (ch as Node3D).global_position, audit, nm)
			elif nm == "Tufts":
				# HEADLESS LIMIT: the dummy renderer does not retain MultiMesh
				# per-instance transforms (get_instance_transform returns
				# identity off-device), so the batch's placement can only be
				# verified in the live engine. Count it, do not measure it.
				var mm2: MultiMesh = (ch as Node3D).get("multimesh")
				audit["tufts"] = int(audit.get("tufts", 0)) + (mm2.instance_count if mm2 != null else 0)

	print("FIELD3 checked=%d worst_below=%.2f worst_above=%.2f bad=%d hist={seat=%d proud=%d low=%d sunk=%d deep=%d float=%d}" % [
		int(audit["checked"]), float(audit["worst_below"]),
		float(audit["worst_above"]), int(audit["bad"]),
		int(audit.get("seat", 0)), int(audit.get("proud", 0)),
		int(audit.get("low", 0)), int(audit.get("sunk", 0)),
		int(audit.get("deep", 0)), int(audit.get("float", 0))])
	# --- 3) THE TRAVEL CENSUS (per-SITE band across all 20 faces) ---
	# Derive the detail tier for each face's chunks (the fresh derive is
	# pure/deterministic), bucketing every site by ITS OWN biome band.
	# Sampled sparsely (stride) so the census stays cheap.
	var by_band := {}
	var cpe: int = PropChunk.cells_per_edge(depth)
	var stride: int = maxi(1, cpe / 8)
	for f in range(20):
		for i in range(0, cpe, stride):
			for j in range(0, cpe, stride):
				var key: int = PropChunk.make_key(f, i, j)
				var fresh: Dictionary = pl.derive_fresh(key)
				for rec in fresh.get("instances", []):
					if int(rec.get("family", -1)) != pl.FAMILY_DETAIL:
						continue
					var band_key: int = int(rec.get("bid", -1))
					var kind_key: String = str(KIND_NAMES.get(int(rec["kind"]), "?"))
					var bucket: Dictionary = by_band.get(band_key, {})
					bucket[kind_key] = int(bucket.get(kind_key, 0)) + 1
					by_band[band_key] = bucket
				if not fresh.get("tufts", []).is_empty():
					# Tufts carry no bid; bucket by the chunk center's biome.
					var cbid: int = provider.biome_id(PropChunk.chunk_center_dir(key, depth))
					var tb: Dictionary = by_band.get(cbid, {})
					tb["tuft"] = int(tb.get("tuft", 0)) + fresh["tufts"].size()
					by_band[cbid] = tb
	for band_key in by_band:
		print("BIOME id=%d sites_by_kind=%s" % [band_key, str(by_band[band_key])])
	quit(0)
