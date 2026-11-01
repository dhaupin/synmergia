extends SceneTree

## Map ping receipt (the cheap-pair round, world_map leg):
##   click ON a quest waypoint marker -> waypoint_clicked (the declared
##   signal, real emit; last_waypoint_hit() carries the marker label)
##   click on the canvas -> map_clicked with a TRUE world position
##   (not a fabricated flat 8km guess), then the ping routes through
##   WaypointService.create_waypoint + activate_waypoint (the beacon's
##   own law). Run:
##   godot --headless --path . --script res://tests/test_map_ping_route.gd

var _wp_clicked: Vector3 = Vector3.INF
var _map_clicked: Vector3 = Vector3.INF

func _initialize() -> void:
	# Autoload-lag law (test_slot_container_open): the autoload set and
	# the child _ready pass live AFTER _initialize -- body runs on the
	# first idle frame, never from _init() and never inline here.
	_run.call_deferred()

func _run() -> void:
	var map_script: GDScript = load("res://ui/components/world_map.gd")
	if map_script == null or not map_script.can_instantiate():
		push_error("FAIL: world_map.gd did not load")
		quit(1)
		return
	var wm = map_script.new()
	root.add_child(wm)
	wm.size = Vector2(800, 600)
	wm.add_waypoint("quest_pin_probe", Vector3(1500.0, 5.0, -900.0), "Wolf Den", 0)
	var marker: Control = wm._entity_markers["quest_pin_probe"]["marker"]
	marker.position = Vector2(100, 100)
	wm.map_clicked.connect(_on_map_clicked_captured)
	wm.waypoint_clicked.connect(_on_waypoint_clicked_captured)

	# 1. Click ON the quest marker: waypoint_clicked fires with the
	# marker's world position; map_clicked stays silent for that click.
	wm._handle_map_click(Vector2(101, 101))
	var quest_pos := Vector3(1500.0, 5.0, -900.0)
	if _wp_clicked.distance_to(quest_pos) > 1.0:
		push_error("FAIL: waypoint_clicked did not fire with the marker's position (%s)" % str(_wp_clicked))
		quit(1)
		return
	print("[OK] quest-marker click emitted waypoint_clicked at the marker position")
	if _map_clicked != Vector3.INF:
		push_error("FAIL: map_clicked fired on a quest-marker hit (double routing)")
		quit(1)
		return
	var hit: Dictionary = wm.last_waypoint_hit()
	if str(hit.get("label", "")) != "Wolf Den":
		push_error("FAIL: last_waypoint_hit() did not carry the marker label (%s)" % str(hit))
		quit(1)
		return
	print("[OK] last_waypoint_hit() carries the clicked marker's label (the Quest ping names its waypoint)")

	# 2. Canvas click: map_clicked fires ONCE with a true, finite
	# world position on the world shell.
	wm._handle_map_click(Vector2(400, 300))
	if _map_clicked == Vector3.INF:
		push_error("FAIL: map_clicked did not fire for a canvas click")
		quit(1)
		return
	if not _map_clicked.is_finite() or _map_clicked == Vector3.ZERO:
		push_error("FAIL: map_clicked carried no usable world position (%s)" % str(_map_clicked))
		quit(1)
		return
	if _map_clicked.length() > 100000.0:
		push_error("FAIL: map_clicked position outside world bounds (%s)" % str(_map_clicked))
		quit(1)
		return
	print("[OK] canvas click emitted map_clicked with a real world position (%s)" % str(_map_clicked))
	if not wm.last_waypoint_hit().is_empty():
		push_error("FAIL: canvas click left stale waypoint hit bookkeeping")
		quit(1)
		return

	# 3. The service leg the HUD routes into: create + activate is the
	# beacon's own law.
	var wsvc: Node = root.get_node_or_null("WaypointService")
	if wsvc == null:
		push_error("FAIL: WaypointService autoload not live in script mode")
		quit(1)
		return
	var player_id := "probe_map_ping"
	var created: Dictionary = wsvc.create_waypoint(player_id, "Map Marker", _map_clicked, "")
	if not bool(created.get("success", false)):
		push_error("FAIL: create_waypoint rejected the ping position: %s" % str(created))
		quit(1)
		return
	var wp: Dictionary = created["waypoint"]
	var wp_id := str(wp.get("id", ""))
	if wp_id == "":
		push_error("FAIL: create_waypoint returned no id")
		quit(1)
		return
	var activated: Dictionary = wsvc.activate_waypoint(player_id, wp_id)
	if not bool(activated.get("success", false)):
		push_error("FAIL: activate_waypoint rejected the fresh ping: %s" % str(activated))
		quit(1)
		return
	var active: Dictionary = wsvc.get_active_waypoint(player_id)
	if active.is_empty():
		push_error("FAIL: no active waypoint after activation")
		quit(1)
		return
	var active_pos := Vector3(
		float(active.get("position_x", 0.0)),
		float(active.get("position_y", 0.0)),
		float(active.get("position_z", 0.0)))
	if active_pos.distance_to(_map_clicked) > 1.0:
		push_error("FAIL: the active waypoint is not the clicked position (%s vs %s)" % [str(active_pos), str(_map_clicked)])
		quit(1)
		return
	print("[OK] WaypointService created + activated the ping (beacon law owns tracking)")
	wm.queue_free()
	print("--- MAP PING ROUTE: ok=true ---")
	quit(0)

func _on_waypoint_clicked_captured(pos: Vector3) -> void:	_wp_clicked = pos

func _on_map_clicked_captured(pos: Vector3) -> void:
	_map_clicked = pos
