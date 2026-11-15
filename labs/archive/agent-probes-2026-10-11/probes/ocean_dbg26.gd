extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	var ur := Vector3(0, -31, 0)
	# volume_at for the inside-stone point: crater local branch: y -31 < floor_y -30 -> REFUSED.
	# shelf local branch: y -31 >= floor_y -60? YES. horiz 0 <= 400. SHELF CLAIMS THE STONE.
	print("vol inside=", svc.volume_at(ur).id if svc.volume_at(ur) != null else "null")
	# and shelf sample at (0,-5,0): vol = crater (crater reach 40 > shelf reach 400? no:
	# crater reach=40, shelf reach=400; tie horiz 0; first claimant wins -> whichever first in dict).
	# The specificity rule uses REACH, but both claim y=-5: crater y ok (-5 <= -4? NO! -5 > -4? surface -6+2=-4; -5 < -4 so INSIDE y band [-30,-4]) yes claims reach 40. shelf claims reach 400. 40 < 400 -> crater should win. But shelf won before? dbg24 said vol=crater for (0,-5). Correct!
	# But dbg24 shelf sample at (0,-5,0) WITH shelf passed explicitly -> 5.0 correct.
	# The failing check is volume_at(below)==shelf where below=(0,-5,0): crater WINS by specificity. THE TEST EXPECTATION IS WRONG -- at (0,-5,0) the crater (reach 40) is MORE SPECIFIC than the shelf (reach 400). The real fix: the two volumes are far apart in the world; the probe should test the shelf in the shelf's own horizontal reach (e.g. x=1000) and the crater near x=0.
	print("vol(1000,-5,0)=", svc.volume_at(Vector3(1000,-5,0)).id if svc.volume_at(Vector3(1000,-5,0)) != null else "null")
	quit(0)
