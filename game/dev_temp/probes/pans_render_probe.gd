## pans_render_probe - the LIVE-STREAM receipt for the Sun Pans
## atoll. The travel census proved the derive LAW produces desert
## sites; this boot proves the engine actually LOADS face 12 when a
## player sails to the bearing:
##   1) boot the 20 km globe (the ordinary scale),
##   2) hold the streamer aim at the pans bearing every frame (the
##      globe's own per-frame update coexists; a lone update() call
##      is reverted and face 12 unloads -- the per-frame hold is
##      what a real sail is),
##   3) drain the derive payments DURING the hold,
##   4) census face 12 IMMEDIATELY after the final update (the sync
##      law installs the mesh inside the call; anything left to a
##      later frame lets the spawn player's drift loop retake the
##      want-set and unload it).
## Run headless: godot --headless --path . --script res://dev_temp/probes/pans_render_probe.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
const PANS_FACE := 12
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const FaceCheck = preload("res://core/frame/math/icosahedral_faces.gd")

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
	var streamer = _globe.get("streamer")
	if streamer == null:
		print("PANS-MISS no streamer on the boot")
		quit(1)
		return
	# THE PROBE'S SAIL COMPANION: the globe's own process loop aims
	# the streamer at the (still-at-spawn) player every frame and
	# unloads face 12 mid-derive -- _apply_derived_props then drops
	# the content (the streamed-out-mid-derive drop). A REAL player
	# standing on the pans holds the aim; the probe mutes the
	# competing loop and drives the aim itself.
	_globe.process_mode = Node.PROCESS_MODE_DISABLED
	var pans: Vector3 = TerrainGen.sun_pans_dir()
	print("PANS face_for_position says: ", FaceCheck.face_for_position(pans * RADIUS, RADIUS))
	for _f in range(300):
		streamer.update(pans * RADIUS)
		await root.get_tree().physics_frame
		if streamer.pending_derive() == 0:
			break
	# The deferred props apply needs a few more held frames.
	for _f in range(10):
		streamer.update(pans * RADIUS)
		await root.get_tree().physics_frame
	var last_ret: Dictionary = streamer.update(pans * RADIUS)
	print("PANS last_update_ret face=", last_ret.get("face"), " loaded=", str(last_ret.get("loaded")), " active=", str(last_ret.get("active")))
	# THE RECEIPT (same frame as the last aim): face 12 loaded? at
	# base level? what does the holder carry?
	var loaded: bool = streamer.is_loaded(PANS_FACE)
	var lvl: int = int(streamer._patch_lvl.get(PANS_FACE, -1))
	print("PANS face12 loaded=", loaded, " lvl=", lvl, " (base=", int(streamer._level_for_edge()), ")")
	var holder = streamer._prop_holders.get(PANS_FACE)
	if holder == null:
		print("PANS-MISS face 12 holder absent")
		quit(1)
		return
	var counts := {}
	for ch in holder.get_children():
		var nm := String(ch.name)
		var label := nm
		for pre in ["Flower", "Bush", "Tree", "Ore", "Scree", "Rock", "DetailTuftBatch", "GrassField", "Shell", "Wrack"]:
			if nm.begins_with(pre):
				label = pre
				break
		var n: int = 1
		var mm: MultiMesh = ch.get("multimesh")
		if mm != null:
			n = mm.instance_count
		counts[label] = int(counts.get(label, 0)) + n
	print("PANS face12 holder=", str(counts))
	var sites: Array = streamer._derive_detail_sites(PANS_FACE)
	var kinds := {}
	for rec in sites:
		kinds[int(rec["kind"])] = int(kinds.get(int(rec["kind"]), 0)) + 1
	print("PANS face12 derive_kinds=", str(kinds), " (0=ore 3=tuft)")
	print("PANS-OK")
	quit(0)
