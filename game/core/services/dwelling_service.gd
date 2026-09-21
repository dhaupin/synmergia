## DwellingService - plots, purchase, and placement of guards/ankhs.
##
## Housing + guards were built to share interfaces on purpose:
## PlacementAccess (core/schemas/placement_access.gd) is the single
## ownership-scope vocabulary, and placed objects (house guards,
## personal ankhs) are configured through the same evaluate() gate so
## guild halls / faction halls / personal houses all resolve access the
## same way.
##
## Flow: register_plot (world builder) -> purchase_plot (player pays)
## -> place_house_guard / place_personal_ankh (250k / 100k gold).
## Every placed object lands inside the plot's access scope, so a
## guild-owned hall could later re-stamp access.scope = GUILD and the
## same guard/ankh rules follow automatically.
##
## Commands: /buyplot, /placeguard, /placeankh, /plotinfo (wired in
## ChatService; this service exposes handle_dwelling_command).
extends Node

const GuardDataScript = preload("res://core/schemas/guard_data.gd")
const PlacementAccessScript = preload("res://core/schemas/placement_access.gd")
const GuardEntityScript = preload("res://entities/guard.gd")
const SpawnMetadataScript = preload("res://core/events/spawn_metadata.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const ANKH_SCRIPT_PATH := "res://core/schemas/ankh.gd"  # runtime load (class_name Ankh)

signal plot_purchased(player_id: String, plot_id: String, price: int)
signal object_placed(player_id: String, plot_id: String, object_type: String, object_id: String)

const DEFAULT_PLOT_PRICE := 50000
const HOUSE_GUARD_COST := 250000   # The 250k-gold dream, as requested.
const PERSONAL_ANKH_COST := 100000

var _plots: Dictionary = {}        # plot_id -> Dictionary
var _test_overrides: Dictionary = {}  # service name -> node (test seams)

func _ready() -> void:
	GameLog.info("DwellingService ready")

## ------------------------------------------------------------------
## SERVICE RESOLUTION (lazy; test seams)
## ------------------------------------------------------------------

func _svc(service_name: String):
	if _test_overrides.has(service_name):
		return _test_overrides[service_name]
	return get_node_or_null(NodePath("/root/" + service_name))

## Test seam: force a service dependency to a stub.
func set_service_override(service_name: String, node) -> void:
	_test_overrides[service_name] = node

## Test seam: wipe all runtime state.
func clear_test_state() -> void:
	_plots.clear()
	_test_overrides.clear()

## ------------------------------------------------------------------
## PLOTS
## ------------------------------------------------------------------

## Register a purchasable plot. Call from scene/world builders.
## access is a PlacementAccess (defaults to personal-on-purchase).
func register_plot(plot_id: String, zone_id: String, center: Vector3, radius: float = 12.0, price: int = DEFAULT_PLOT_PRICE) -> Dictionary:
	var plot := {
		"id": plot_id,
		"zone_id": zone_id,
		"center": center,
		"radius": radius,
		"price": price,
		"owner_id": "",
		"guard_id": "",
		"ankh_id": "",
	}
	_plots[plot_id] = plot
	return plot

## Test seam: register a plot already owned by a player (skips cost).
func register_test_plot(plot_id: String, zone_id: String, owner_id: String, center: Vector3 = Vector3.ZERO, radius: float = 12.0) -> Dictionary:
	var plot := register_plot(plot_id, zone_id, center, radius, 0)
	plot["owner_id"] = owner_id
	return plot

func get_plot(plot_id: String) -> Dictionary:
	return _plots.get(plot_id, {})

func get_plots() -> Dictionary:
	return _plots

func get_plots_for_player(player_id: String) -> Array:
	var owned: Array = []
	for plot_id in _plots:
		if str(_plots[plot_id]["owner_id"]) == player_id:
			owned.append(_plots[plot_id])
	return owned

## Nearest plot whose radius contains the position. owned_filter:
## "" = any, "owned" = owned plots only, "unowned" = purchasable only.
func get_nearest_plot(pos: Vector3, owned_filter: String = "") -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for plot_id in _plots:
		var plot: Dictionary = _plots[plot_id]
		if owned_filter == "owned" and str(plot["owner_id"]) == "":
			continue
		if owned_filter == "unowned" and str(plot["owner_id"]) != "":
			continue
		var center: Vector3 = plot["center"]
		var dist := center.distance_to(pos)
		if dist <= float(plot["radius"]) and dist < best_dist:
			best_dist = dist
			best = plot
	return best

## ------------------------------------------------------------------
## PURCHASE
## ------------------------------------------------------------------

## Try to buy the plot for the player. Deducts gold via the duck-typed
## `gold` property (PlayerController and PlayerManager both carry it).
func purchase_plot(player, plot_id: String) -> Dictionary:
	if player == null or not ("entity_id" in player):
		return {"ok": false, "reason": "invalid_player"}
	var pid := str(player.entity_id)
	var plot: Dictionary = _plots.get(plot_id, {})
	if plot.is_empty():
		return {"ok": false, "reason": "unknown_plot"}
	if str(plot["owner_id"]) != "":
		return {"ok": false, "reason": "already_owned"}
	if not get_plots_for_player(pid).is_empty():
		return {"ok": false, "reason": "already_owns_plot"}
	var price := int(plot["price"])
	if not _spend_gold(player, price):
		return {"ok": false, "reason": "insufficient_gold"}
	plot["owner_id"] = pid
	# Ownership scope follows the deed: personal by default (owner +
	# any explicit allow list already on the plot's access).
	if plot.has("access") and plot["access"] != null:
		plot["access"].owner_id = pid
	plot_purchased.emit(pid, plot_id, price)
	GameLog.info("DwellingService: %s purchased plot %s for %d gold" % [pid, plot_id, price])
	return {"ok": true, "plot": plot}

## ------------------------------------------------------------------
## PLACEMENT (guards + ankhs share the same validation)
## ------------------------------------------------------------------

## Shared validation. Returns "" when allowed, else a denial reason.
func _validate_placement(player, plot_id: String, cost: int, kind: String) -> String:
	if player == null or not ("entity_id" in player):
		return "invalid_player"
	var plot: Dictionary = _plots.get(plot_id, {})
	if plot.is_empty():
		return "unknown_plot"
	if str(plot["owner_id"]) != str(player.entity_id):
		return "not_owner"
	var existing := "guard_id" if kind == "guard" else "ankh_id"
	if str(plot[existing]) != "":
		return "already_placed"
	if not _spend_gold(player, cost):
		return "insufficient_gold"
	return ""

## Place a PERSONAL house guard on an owned plot. The 250k dream.
## The guard is owned by the buyer, friendly to the buyer, hostile
## (TRESPASS + ATTACKED) to everyone else near the plot.
func place_house_guard(player, plot_id: String, guard_name: String = "House Guard"):
	var reason := _validate_placement(player, plot_id, HOUSE_GUARD_COST, "guard")
	if reason != "":
		return null
	var pid := str(player.entity_id)
	var plot: Dictionary = _plots[plot_id]

	var data: GuardData = GuardDataScript.house_guard(
		"house_guard_%s_%d" % [pid, Time.get_ticks_msec()],
		guard_name, pid, [pid])
	data.access = PlacementAccessScript.personal(pid)
	data.post_position = plot["center"]

	var guard = GuardEntityScript.new()
	guard.entity_id = data.id
	guard.display_name = guard_name
	guard.guard_data = data
	guard.attach_guard_ai(data)
	if "level" in guard:
		guard.level = data.level
	if _spawn_at(guard, plot):
		plot["guard_id"] = data.id
		_register_with_entity_service(guard, plot["zone_id"])
		object_placed.emit(pid, plot_id, "guard", data.id)
		GameLog.info("DwellingService: %s placed house guard on plot %s" % [pid, plot_id])
		return guard
	guard.queue_free()
	return null

## Place a PERSONAL ankh on an owned plot (private respawn point).
## Bind access is stamped with the same PlacementAccess scope, so the
## ankh is usable by the owner (and allowed ids) only.
func place_personal_ankh(player, plot_id: String):
	var reason := _validate_placement(player, plot_id, PERSONAL_ANKH_COST, "ankh")
	if reason != "":
		return null
	var pid := str(player.entity_id)
	var plot: Dictionary = _plots[plot_id]

	var ankh_script = load(ANKH_SCRIPT_PATH)
	var ankh = ankh_script.new()
	var ankh_id := "ankh_plot_%s_%d" % [pid, Time.get_ticks_msec()]
	ankh.ankh_id = ankh_id
	ankh.display_name = "Personal Ankh"
	ankh.description = "A private resurrection ankh bound to your plot."
	ankh.zone_id = str(plot["zone_id"])
	ankh.ankh_type = ankh.AnkhType.PERSONAL
	ankh.access = PlacementAccessScript.personal(pid)
	ankh.position = plot["center"]

	if _spawn_at(ankh, plot):
		plot["ankh_id"] = ankh_id
		object_placed.emit(pid, plot_id, "ankh", ankh_id)
		GameLog.info("DwellingService: %s placed personal ankh on plot %s" % [pid, plot_id])
		return ankh
	ankh.queue_free()
	return null

## Shared spawn: parent to the scene (or root in script mode), put the
## object at the plot center.
func _spawn_at(node: Node3D, plot: Dictionary) -> bool:
	var tree := get_tree() if is_inside_tree() else null
	if tree == null:
		return false
	var parent: Node = tree.current_scene
	if parent == null:
		parent = tree.root
	parent.add_child(node)
	node.position = plot["center"]
	return true

func _register_with_entity_service(entity, zone_id: String) -> void:
	var es = _svc("EntityService")
	if es == null or not es.has_method("register_entity"):
		return
	var metadata = SpawnMetadataScript.enemy(
		entity.display_name, zone_id, entity.global_position, entity.level)
	es.register_entity(entity, metadata)

## ------------------------------------------------------------------
## GOLD (duck-typed: PlayerController + test stubs)
## ------------------------------------------------------------------

func _spend_gold(player, amount: int) -> bool:
	if player == null or amount < 0:
		return false
	if not ("gold" in player):
		return false
	if int(player.gold) < amount:
		return false
	player.gold = int(player.gold) - amount
	if "gold_changed" in player and player.gold_changed is Signal:
		player.gold_changed.emit(player.gold)
	return true

## ------------------------------------------------------------------
## CHAT COMMANDS (/buyplot /placeguard /placeankh /plotinfo)
## ------------------------------------------------------------------

func handle_dwelling_command(sender_id: String, command: String, args: Array) -> bool:
	var es = _svc("EntityService")
	var player = es.get_entity(sender_id) if es != null and es.has_method("get_entity") else null
	if player == null:
		return false
	var pos: Vector3 = player.global_position if "global_position" in player else Vector3.ZERO

	match command:
		"buyplot":
			var plot := get_nearest_plot(pos, "unowned")
			if plot.is_empty():
				_notify(sender_id, "No purchasable plot here.")
				return true
			var result := purchase_plot(player, str(plot["id"]))
			if result["ok"]:
				_notify(sender_id, "Plot %s purchased for %d gold." % [str(plot["id"]), int(plot["price"])])
			else:
				_notify(sender_id, "Purchase failed: %s." % str(result["reason"]))
			return true
		"placeguard":
			return _cmd_place(sender_id, player, pos, "guard", args)
		"placeankh":
			return _cmd_place(sender_id, player, pos, "ankh", args)
		"plotinfo":
			var plot := get_nearest_plot(pos, "")
			if plot.is_empty():
				_notify(sender_id, "No plot nearby.")
				return true
			var owner := str(plot["owner_id"])
			var desc := "Plot %s: %s, price %d" % [
				str(plot["id"]),
				"owned by %s" % owner if owner != "" else "for sale",
				int(plot["price"])]
			_notify(sender_id, desc)
			return true
		_:
			return false

func _cmd_place(sender_id: String, player, pos: Vector3, kind: String, args: Array) -> bool:
	var plot := get_nearest_plot(pos, "owned")
	if plot.is_empty() or str(plot["owner_id"]) != sender_id:
		_notify(sender_id, "You must stand on your own plot.")
		return true
	var placed = null
	if kind == "guard":
		var guard_name := str(args[0]) if not args.is_empty() else "House Guard"
		placed = place_house_guard(player, str(plot["id"]), guard_name)
	else:
		placed = place_personal_ankh(player, str(plot["id"]))
	if placed == null:
		_notify(sender_id, "Placement failed (not owner, already placed, or not enough gold).")
	return true

## Player feedback. NotificationService may be absent in script mode.
func _notify(player_id: String, message: String) -> void:
	var ns = _svc("NotificationService")
	if ns != null and ns.has_method("notify"):
		ns.notify(NotifKind.AUTO_ACTION, message, "DwellingService",
			"dwelling:%s:%s" % [player_id, message.hash()], {}, player_id)
	else:
		GameLog.info("DwellingService [%s]: %s" % [player_id, message])
