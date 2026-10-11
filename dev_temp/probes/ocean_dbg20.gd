extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	var p := Vector3(0, -12, 0)
	# The bug hunt: bool(v.floor_is_radial) on a .tres-loaded field.
	# type=1 = bool? In Godot, TYPE_BOOL=1. false -> radial branch
	# skipped, local runs. Yet result null. Try shelf first branch:
	# radial=false -> local branch. crater: local. Both claim, horiz
	# tie 0.0, `horiz < best_dist` false for second (0<0 false) ->
	# first wins. First in dict values: which? insertion = load order
	# (dir listing). If crater first: crater wins. Result was null...
	# unless best_dist init -1.0 and `best == null or horiz <
	# best_dist` -- crater: best==null true -> best=crater,
	# best_dist=0. shelf: horiz 0 < 0 false -> keep crater. NOT null!
	# Unless the LOCAL branch never ran: bool(crater.floor_is_radial)
	# -- floor_is_radial=false, bool() = false -> radial branch SKIPPED
	# and local runs. But wait -- the SERVICE still has the OLD
	# volume_at? Verify the service script content live:
	var f = FileAccess.open("res://core/services/ocean_service.gd", FileAccess.READ)
	var txt := f.get_as_text()
	print("has_local_branch=", txt.contains("LOCAL pool: claims"), " has_tie=", txt.contains("horiz < best_dist"))
	# Is the autoload instance running old code? Compare script hash
	print("autoload script=", svc.get_script().resource_path, " same=", svc.get_script() == load("res://core/services/ocean_service.gd"))
	quit(0)
