## probe_biodiversity_v7 - the species-shape census for the v7 leg.
## Boots the streamed globe at the planet scale and counts the NEW
## v7 content across the streamed set: species-variant trunks, bare
## snag canopies, scree collars, mushrooms, mycelium patches, and
## vine hangs (short thin cylinders hung below a tree's local +y).
## Run headless:  godot --headless --path game --script res://tests/probe_biodiversity_v7.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const RADIUS := 20000.0

var _globe: Node3D

func _init() -> void:
	call_deferred("_run")

func _strip_digits(n: String) -> String:
	while n.length() > 1 and (n[n.length() - 1].to_lower() in "0123456789"):
		n = n.substr(0, n.length() - 1)
	return n

func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(6):
		await process_frame
	for _i in range(90):
		await root.get_tree().physics_frame
	var streamer = _globe.get("streamer")
	var waited := 0
	while streamer._prop_pending() > 0 and waited < 600:
		await root.get_tree().physics_frame
		waited += 1
	var n_faces := 0
	var trees := 0
	var species_variants := 0
	var bare_snags := 0
	var vines := 0
	var scree := 0
	var mushrooms := 0
	var mycelium := 0
	var faces_scree := {}
	var faces_mushroom := {}
	for face in streamer.active_faces():
		n_faces += 1
		var holder = streamer._prop_holders.get(face)
		if holder == null or not is_instance_valid(holder):
			continue
		for prop in holder.get_children():
			var base := _strip_digits(String(prop.name))
			if base == "Tree":
				trees += 1
				var has_canopy := false
				for child in prop.get_children():
					if child is MeshInstance3D and child.mesh is SphereMesh:
						has_canopy = true
				if not has_canopy:
					bare_snags += 1
				else:
					# Variant canopy: not the v4 default (h = 1.8 * r).
					for child in prop.get_children():
						if child is MeshInstance3D and child.mesh is SphereMesh:
							var sm: SphereMesh = child.mesh
							if not is_equal_approx(sm.height, sm.radius * 1.8):
								species_variants += 1
				for child in prop.get_children():
					if child is MeshInstance3D and child.mesh is CylinderMesh \
							and child.mesh.height < 1.0:
						vines += 1
			elif base == "Scree":
				scree += 1
				faces_scree[face] = true
			elif base == "Mushroom":
				mushrooms += 1
				faces_mushroom[face] = true
			elif base == "Mycelium":
				mycelium += 1
	print("BIO_CENSUS_v7:")
	print("  live_faces=", n_faces)
	print("  trees_nodes=", trees)
	print("  species_variant_canopies=", species_variants)
	print("  bare_snags=", bare_snags)
	print("  vines=", vines)
	print("  scree_rubble=", scree, " faces_with=", faces_scree.size())
	print("  mushrooms=", mushrooms, " faces_with=", faces_mushroom.size())
	print("  mycelium_patches=", mycelium)
	quit(0)
