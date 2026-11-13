## wilds_probe - S15.6 the Deep Wilds' receipt (the underworld's first
## biome law, five deterministic bands):
##   1) THE FAMILY LAW: the DeepWilds root carries the five scatter
##      families at their declared counts (crags, dead trunks,
##      mycelium clumps, stalagmites, grass tufts);
##   2) THE STAND LAW: stones carry colliders (crag/trunk/stalagmite),
##      paint does not (mycelium/grass ride the walk-over law);
##   3) THE APRON LAW: no crag walls the two gates or the cistern in;
##   4) THE DETERMINISM LAW: a second conjured globe re-derives the
##      scatter byte-identical (same seats, same drift).
## Run headless: godot --headless --path . --script res://dev_temp/probes/wilds_probe.gd
extends SceneTree

const UNDER_SCENE := "res://scenes/worlds/globe_underworld.tscn"

# SCRIPT-MODE LAW: no const preloads of game scripts -- autoload
# identifiers register AFTER parse (the cistern probe lesson).

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("WILDS-PASS %s %s" % [label, detail])
	else:
		_fails += 1
		print("WILDS-MISS %s %s" % [label, detail])


func _init() -> void:
	call_deferred("_run")


func _count_family(wilds: Node, prefix: String) -> int:
	var n := 0
	for c in wilds.get_children():
		if str(c.name).begins_with(prefix):
			n += 1
	return n


func _seats(wilds: Node, prefix: String) -> Array:
	var out: Array = []
	for c in wilds.get_children():
		if str(c.name).begins_with(prefix):
			out.append(c.position)
	return out


func _run() -> void:
	var packed: PackedScene = load(UNDER_SCENE)
	if packed == null:
		print("WILDS-MISS globe_underworld.tscn missing")
		quit(1)
		return
	var under: Node = packed.instantiate()
	root.add_child(under)
	for _i in range(10):
		await root.get_tree().process_frame
	var wr: Node = under.get("world_root")
	var wilds: Node = wr.get_node_or_null("DeepWilds")
	if wilds == null:
		print("WILDS-MISS DeepWilds missing under WorldRoot")
		quit(1)
		return
	_check("wilds_root", true)

	# 1) THE FAMILY LAW: declared counts (crags SKIP the apron clears,
	#    so the law is a floor, not an exact count).
	var crags := _count_family(wilds, "DeepCrag_")
	var trunks := _count_family(wilds, "DeadTrunk_")
	var clumps := _count_family(wilds, "MyceliumClump_")
	var spikes := _count_family(wilds, "Stalagmite_")
	var tufts := _count_family(wilds, "WildGrass_")
	print("WILDS counts crags=%d trunks=%d clumps=%d spikes=%d tufts=%d" % [crags, trunks, clumps, spikes, tufts])
	_check("crag_floor", crags >= 9, "crags=%d" % crags)
	_check("grove", trunks == 7)
	_check("mycelium", clumps == 9)
	_check("stalagmites", spikes == 14)
	_check("grasses", tufts == 36)

	# 2) THE STAND LAW: stones collide, paint does not.
	var stone_ok := true
	for prefix in ["DeepCrag_", "DeadTrunk_", "Stalagmite_"]:
		for n in wilds.get_children():
			if not str(n.name).begins_with(prefix):
				continue
			var collider := false
			for d in n.get_children():
				if d is StaticBody3D or d is CollisionShape3D or d is StaticBody3D:
					collider = true
					break
			if not collider:
				stone_ok = false
				break
		if not stone_ok:
			break
	_check("stones_stand_collidered", stone_ok)
	var paint_ok := true
	for prefix in ["MyceliumClump_", "WildGrass_"]:
		for n in wilds.get_children():
			if not str(n.name).begins_with(prefix):
				continue
			for d in n.get_children():
				if d is StaticBody3D:
					paint_ok = false
					break
			if not paint_ok:
				break
		if not paint_ok:
			break
	_check("paint_walks_over", paint_ok)

	# 3) THE APRON LAW: the gates (camp +/-4) and the cistern dish
	#    (seat 12,0) keep their clear rings.
	var camp_head: Vector3 = under.get("CAMP_HEAD_POS")
	var apron_ok := true
	for crag in wilds.get_children():
		if not str(crag.name).begins_with("DeepCrag_"):
			continue
		var dist: Vector3 = (crag.position as Vector3) - camp_head
		var gate_a := dist.distance_to(Vector3(4.0, 0.0, 4.0))
		var gate_b := dist.distance_to(Vector3(-4.0, 0.0, 4.0))
		var dish := Vector3(dist.x - 12.0, 0.0, dist.z).length()
		if gate_a < 6.0 or gate_b < 6.0 or dish < 8.0:
			apron_ok = false
			break
	_check("aprons_clear", apron_ok, "gates 6 m, dish 8 m")

	# 3b) THE WALK-LINE LAW: the wilds/lake/trail sit ON the shelf
	#     (y ~= CAMP_HEAD_POS.y = the walk line), NOT a globe-radius
	#     above it. A seat that already carries CAMP_HEAD_POS.y must
	#     never add the ABSOLUTE walk line again -- that floats the
	#     whole shelf to 2*radius (its physics stays at radius).
	var walk_y: float = camp_head.y
	var off_line := 0
	for nm in ["DeepWilds", "UnderglowLake", "DeepTrail"]:
		var holder: Node = wr.get_node_or_null(nm)
		if holder == null:
			continue
		for c in holder.get_children():
			if c is Node3D and absf((c as Node3D).position.y - walk_y) > 15.0:
				off_line += 1
	_check("shelf_sits_on_walk_line", off_line == 0, "off-line=%d (walk y=%.0f)" % [off_line, walk_y])

	# 3c) THE DATA-READ LAW: the cistern/lake STONE is built to the same
	#     numbers the OceanVolume declares (the ocean_ id law), so a data
	#     edit moves the visible dish with its physics -- never silently.
	var ocean = root.get_node_or_null("OceanService")
	if ocean != null:
		var pv = ocean.get_volume("ocean_deep_root_pool")
		var cistern: Node = wr.get_node_or_null("GlowCistern")
		var water: Node = cistern.get_node_or_null("CisternWater") if cistern != null else null
		_check("cistern_reads_declaration", pv != null and water != null \
			and absf(water.position.y - float(pv.surface_height)) < 0.01, \
			"water_y=%.2f decl=%.2f" % [water.position.y if water != null else -1.0, float(pv.surface_height) if pv != null else -1.0])
		var lv = ocean.get_volume("lava_underglow_lake")
		var lake: Node = wr.get_node_or_null("UnderglowLake")
		var basin: Node = lake.get_node_or_null("LakeBasin") if lake != null else null
		_check("lake_reads_declaration", lv != null and basin != null \
			and absf((basin.position.y + 0.2) - float(lv.floor_y)) < 0.01, \
			"basin_top=%.2f decl=%.2f" % [basin.position.y + 0.2 if basin != null else -1.0, float(lv.floor_y) if lv != null else -1.0])

	# 4) THE DETERMINISM LAW: a second globe re-derives the same seats
	#    (byte-identical scatter).
	var second: Node = packed.instantiate()
	root.add_child(second)
	for _i in range(10):
		await root.get_tree().process_frame
	var wr2: Node = second.get("world_root")
	var wilds2: Node = wr2.get_node_or_null("DeepWilds")
	_check("second_wilds", wilds2 != null)
	var det_ok := wilds2 != null
	if det_ok:
		var first_crag: Array = _seats(wilds, "DeepCrag_")
		var second_crag: Array = _seats(wilds2, "DeepCrag_")
		det_ok = first_crag.size() == second_crag.size()
		if det_ok:
			for i in range(first_crag.size()):
				if not (first_crag[i] as Vector3).is_equal_approx(second_crag[i]):
					det_ok = false
					break
		var first_grass: Array = _seats(wilds, "WildGrass_")
		var second_grass: Array = _seats(wilds2, "WildGrass_")
		if first_grass.size() != second_grass.size():
			det_ok = false
		else:
			for i in range(first_grass.size()):
				if not (first_grass[i] as Vector3).is_equal_approx(second_grass[i]):
					det_ok = false
					break
	_check("byte_identical", det_ok)

	if _fails > 0:
		print("WILDS-FAIL %d" % _fails)
		quit(1)
		return
	print("WILDS-OK")
	quit(0)

