## pans_pair_probe - the Sun Pans zone+gateway pair registration
## receipt. Boots the project's autoloads headless, re-runs the
## authored-gateway seam (idempotent: known ids skip), and prints the
## zone + gateway the pair should expose. Run headless:
##   godot --headless --path . --script res://dev_temp/probes/pans_pair_probe.gd
extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ws = root.get_node_or_null("WorldService")
	if ws == null:
		print("PAIR-MISS WorldService autoload absent")
		quit(1)
		return
	# The seam already ran in _ready; calling again is the idempotent
	# path (persistence-loaded ids are skipped verbatim).
	ws.call("_register_authored_gateways")
	var gateways: Dictionary = ws.get("_gateways")
	var g = gateways.get("waypoint_sun_pans")
	if g == null:
		print("PAIR-MISS gateway waypoint_sun_pans not registered")
		quit(1)
		return
	print("GATEWAY id=waypoint_sun_pans to_zone=", g.to_zone_id, " type=", g.gateway_type)
	var zm = root.get_node_or_null("ZoneManager")
	if zm == null:
		print("PAIR-MISS ZoneManager autoload absent")
		quit(1)
		return
	zm.call("load_zones")
	var zone = zm.call("get_zone", "zone_sun_pans")
	if zone == null:
		print("PAIR-MISS zone zone_sun_pans not loaded")
		quit(1)
		return
	print("ZONE id=", zone.id, " name=", zone.display_name, " center=", zone.zone_center)
	print("PAIR-OK")
	quit(0)
