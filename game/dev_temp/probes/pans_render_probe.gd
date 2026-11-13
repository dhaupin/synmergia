## pans_render_probe - the LIVE-STREAM receipt for the Sun Pans
## atoll under the clipmap. The travel census proved the derive LAW
## produces desert sites; this boot proves the PropLayer actually
## STREAMS them when a player stands on the pans bearing:
##   1) boot the 20 km globe (the ordinary scale),
##   2) drive the clipmap update at the pans bearing (which streams the
##      PropLayer on the same player position),
##   3) drain the prop build queue DURING the drive,
##   4) census the pans chunks' built props (ore = the desert detail).
## Run headless: godot --headless --path . --script res://dev_temp/probes/pans_render_probe.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
const PANS_FACE := 12
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const FaceCheck = preload("res://core/frame/math/icosahedral_faces.gd")
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")

var _globe: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(10):
		await process_frame
	var clipmap = _globe.get("clipmap")
	if clipmap == null:
		print("PANS-MISS no clipmap on the boot")
		quit(1)
		return
	# The globe's own process loop aims the clipmap at the spawn player;
	# a real sailor holds the pans bearing, so mute the competing loop
	# and drive the aim ourselves.
	_globe.process_mode = Node.PROCESS_MODE_DISABLED
	var pans: Vector3 = TerrainGen.sun_pans_dir()
	print("PANS face_for_position says: ", FaceCheck.face_for_position(pans * RADIUS, RADIUS))
	for _f in range(300):
		clipmap.update(pans * RADIUS)
		await root.get_tree().physics_frame
		var pl = clipmap.prop_layer()
		if pl.pending_build() == 0 and pl.built_count() > 0:
			break
	for _f in range(20):
		clipmap.update(pans * RADIUS)
		await root.get_tree().physics_frame
	var last_ret: Dictionary = clipmap.update(pans * RADIUS)
	print("PANS last_update_ret face=", last_ret.get("face"), " loaded=", str(last_ret.get("loaded")), " active=", str(last_ret.get("active")))
	var pl = clipmap.prop_layer()
	var pc: Vector3 = _globe.get("planet_center")
	# Census the built chunks whose center lies on the pans face.
	var counts := {}
	var pans_chunks: int = 0
	for k in pl._built.keys():
		if PropChunk.face_of(int(k)) != PANS_FACE:
			continue
		pans_chunks += 1
		for ch in (pl._built.get(k) as Node3D).get_children():
			var nm := String(ch.name)
			var label := nm
			var pres: Array = ["Flower", "Bush", "Tree", "Ore", "Scree", "Rock", "Mycelium", "Mushroom", "Shell", "Wrack", "Cattail", "Tufts", "Boulder"]
			for pre in pres:
				if nm.begins_with(pre):
					label = pre
					break
			var n: int = 1
			var mm: MultiMesh = ch.get("multimesh")
			if mm != null:
				n = mm.instance_count
			counts[label] = int(counts.get(label, 0)) + n
	print("PANS face12 built_chunks=", pans_chunks, " holder=", str(counts))
	# THE DERIVE LAW: the pans-center chunk's detail kinds (desert -> ore).
	var ckey: int = PropChunk.chunk_for_dir(pans, 6)
	var data: Dictionary = pl.derive_fresh(ckey)
	var kinds := {}
	for rec in data.get("instances", []):
		if int(rec.get("family", -1)) == 3:
			kinds[int(rec["kind"])] = int(kinds.get(int(rec["kind"]), 0)) + 1
	print("PANS center_chunk derive kinds=", str(kinds), " tufts=", (data.get("tufts", []) as Array).size(), " (desert: sparse ore/tuft, ~1-2 per chunk)")
	if pans_chunks <= 0:
		print("PANS-MISS the pans face streamed no prop chunks")
		quit(1)
		return
	print("PANS-OK")
	quit(0)
