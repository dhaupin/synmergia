## probe_biodiversity_v7 - the species-shape census for the v7 leg.
## Boots the globe at the planet scale and counts the NEW v7 content
## across the PropLayer's built chunks: species-variant trunks, bare
## snag canopies, vines, scree, mushrooms, and mycelium patches.
##
## This is a CENSUS diagnostic (no assertions): it prints the counts.
## The clipmap's PropLayer is the sole flora path now (chunks named
## "PropChunk_%d" carrying Tree/Rock/Boulder/Scree/Mushroom/Mycelium/...
## nodes).
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
	var clipmap = _globe.get("clipmap")
	var waited := 0
	while clipmap.pending_jobs() > 0 and waited < 600:
		await root.get_tree().physics_frame
		waited += 1
	var pl = clipmap.prop_layer()
	var n_chunks := 0
	var trees := 0
	var species_variants := 0
	var bare_snags := 0
	var vines := 0
	var scree := 0
	var mushrooms := 0
	var mycelium := 0
	var chunks_scree := {}
	var chunks_mushroom := {}
	if pl != null:
		for k in pl._built.keys():
			var chunk = pl._built.get(k)
			if chunk == null or not is_instance_valid(chunk):
				continue
			n_chunks += 1
			for prop in chunk.get_children():
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
						for child in prop.get_children():
							if child is MeshInstance3D and child.mesh is SphereMesh:
								var sm: SphereMesh = child.mesh
								if not is_equal_approx(sm.height, sm.radius * 1.8):
									species_variants += 1
					for child in prop.get_children():
						# A vine hang is a THIN tapered cylinder (top_radius
						# ~0.035); the trunk is a fat one (~0.14). Height alone
						# cannot tell them apart (hang_len 1.3-2.1).
						if child is MeshInstance3D and child.mesh is CylinderMesh \
								and child.mesh.top_radius < 0.1:
							vines += 1
				elif base == "Scree":
					scree += 1
					chunks_scree[k] = true
				elif base == "Mushroom":
					mushrooms += 1
					chunks_mushroom[k] = true
				elif base == "Mycelium":
					mycelium += 1
	print("BIO_CENSUS_v7:")
	print("  live_chunks=", n_chunks)
	print("  trees_nodes=", trees)
	print("  species_variant_canopies=", species_variants)
	print("  bare_snags=", bare_snags)
	print("  vines=", vines)
	print("  scree_rubble=", scree, " chunks_with=", chunks_scree.size())
	print("  mushrooms=", mushrooms, " chunks_with=", chunks_mushroom.size())
	print("  mycelium_patches=", mycelium)
	quit(0)
