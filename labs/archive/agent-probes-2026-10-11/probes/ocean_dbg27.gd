extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	# (1000,-5,0): shelf local: y -5 in [-60, 2] ok. horiz = 1000 <= 400? NO -> refused.
	# The shelf's reach is only 400 m -- a shelf is WIDE. Reach for a
	# shelf (no explicit dish) should default WIDE; the crater's 40 m
	# dish is the tight one. Set shelf floor_radius to a real width:
	# the shelf reaches 5000 m. But horiz(0,-5,0)=0 < 5000 -> shelf
	# would also claim the crater's spot with reach 5000 vs crater 40
	# -> crater still wins by specificity. Good.
	# Inside-stone fix: the shelf's local branch must refuse bodies
	# below ITS floor too -- it does: y -31 >= -60 is TRUE so it
	# claims. The shelf's floor is -60; y=-31 is above its floor but
	# BELOW the crater's floor. The shelf should not claim a body the
	# crater's rock occupies... but the shelf cannot know that. The
	# honest answer: inside the crater's stone, the crater's own
	# refusal (-1) must WIN over any other claimant. volume_at must
	# prefer the volume that REFUSES nothing... no -- simplest honest
	# model: volumes do not overlap in XZ. Give the shelf a real
	# XZ span far from the crater (floor_center.x = 3000, radius
	# 5000) and keep the crater at origin. Then (0,-31,0) is inside
	# crater XZ but refused by its floor -> no claimant -> null -> -1.
	print("expect null after data fix")
	quit(0)
