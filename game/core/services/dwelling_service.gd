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

## Placeable stations: the FUNCTIONAL dwellings whose provides_function
## is the station law. One door, mirroring NPCData.get_crafting_station:
## "blacksmith" = the smithy UI (repair), "crafting_forge"/
## "crafting_workbench"/"crafting_alchemy" = RecipeData.Station ids.
## A placed station crafts through the SAME CraftingService.craft gate
## as an NPC's bench -- the world place is a station host, never a
## second gate.
signal plot_purchased(player_id: String, plot_id: String, price: int)
signal object_placed(player_id: String, plot_id: String, object_type: String, object_id: String)
signal object_removed(player_id: String, plot_id: String, object_type: String, object_id: String)
signal house_built(player_id: String, plot_id: String, house_id: String)

const HOUSE_COST := 750000  # the actual house: walls, door, roof, and a roof to sleep under

const DEFAULT_PLOT_PRICE := 50000
const HOUSE_GUARD_COST := 250000   # The 250k-gold dream, as requested.
const PERSONAL_ANKH_COST := 100000

var _plots: Dictionary = {}        # plot_id -> Dictionary
var _test_overrides: Dictionary = {}  # service name -> node (test seams)

## The function -> RecipeData.Station map (the placed-station arm of
## the station law; NPCData.get_crafting_station is the NPC arm).
const STATION_FUNCTIONS: Dictionary = {
	"crafting_forge": 1,
	"crafting_workbench": 2,
	"crafting_alchemy": 3,
}

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

## Place a CRAFT/BUILD station (anvil, forge, workbench, cauldron) on
## an owned plot. dwelling_id is a FUNCTIONAL DwellingData id from
## data/dwellings/. Two station kinds exist:
##   "blacksmith"          -> the repair station (opens BlacksmithUI)
##   "crafting_*"          -> a RecipeData.Station (opens WorkbenchUI
##                            at STATION_FUNCTIONS[function])
## The item is CONSUMED from the crafter's purse (a thing you placed is
## a thing you no longer carry), records the placed object on the plot
## under stations[function], and the interaction law lives in the data
## (is_interactable + interaction_type). Access is STAMPED with the
## plot's PlacementAccess like every other placed object.
func place_station(player, plot_id: String, dwelling_id: String) -> Dictionary:
	if player == null or not ("entity_id" in player):
		return {"ok": false, "reason": "invalid_player"}
	var pid := str(player.entity_id)
	var plot: Dictionary = _plots.get(plot_id, {})
	if plot.is_empty():
		return {"ok": false, "reason": "unknown_plot"}
	if str(plot["owner_id"]) != pid:
		return {"ok": false, "reason": "not_owner"}
	var ds = _svc("DataService")
	# The station law reads the ITEM catalog: placeable dwellings are
	# Item-scripted .tres (merged into _items by load_dwellings), and
	# get_item is the one door that resolves them (get_dwelling's pure
	# DwellingData registry never carries these).
	var dwelling = ds.get_item(dwelling_id) if ds != null and ds.has_method("get_item") else null
	if dwelling == null or not bool(dwelling.get("is_placeable")):
		return {"ok": false, "reason": "unknown_dwelling"}
	var function := str(dwelling.get("provides_function"))
	if function != "blacksmith" and not STATION_FUNCTIONS.has(function):
		return {"ok": false, "reason": "not_a_station"}
	if not plot.has("stations") or plot["stations"] == null:
		plot["stations"] = {}
	var stations: Dictionary = plot["stations"]
	if stations.has(function):
		return {"ok": false, "reason": "station_slot_taken"}
	# The citizen's purse pays IN GOODS, not gold: consume ONE dwelling
	# item from the bag (all-or-nothing; duplicates never eat).
	var inv_svc = _svc("InventoryService")
	var bag = inv_svc.get_inventory(pid) if inv_svc != null and inv_svc.has_method("get_inventory") else null
	if bag == null or not bag.has_method("remove_item_by_id"):
		return {"ok": false, "reason": "no_inventory"}
	if not bag.remove_item_by_id(dwelling_id, 1):
		return {"ok": false, "reason": "item_not_in_bag"}

	# Place a visual anchor node at the plot (the station's world
	# body). Geometry is a plain pedestal box; the craft/repair UI
	# opens from the player's interaction with THIS node.
	var station_node := _build_station_node(dwelling_id, function, stations.size())
	if not _spawn_at(station_node, plot):
		station_node.queue_free()
		# Refund: the purse never loses the thing.
		var refund_item = ds.get_item(dwelling_id) if ds != null and ds.has_method("get_item") else null
		if refund_item != null and bag.has_method("add_item"):
			bag.add_item(refund_item, 1)
		return {"ok": false, "reason": "spawn_failed"}
	stations[function] = {
		"dwelling_id": dwelling_id,
		"node_id": station_node.name,
	}
	if plot.has("access") and plot["access"] != null:
		station_node.set_meta("placement_access", plot["access"])
	object_placed.emit(pid, plot_id, "station", dwelling_id)
	GameLog.info("DwellingService: %s placed %s (%s) on plot %s" % [pid, dwelling_id, function, plot_id])
	return {"ok": true, "station": stations[function], "function": function}

## The station law read for a PLOT: which stations have been placed
## there ({function: true}), so interaction resolution answers
## "can this plot host a craft menu" through data truth, not position
## heuristics. "blacksmith" included -- the repair station is a station.
func get_plot_stations(plot_id: String) -> Dictionary:
	var out := {}
	for function in _plots.get(plot_id, {}).get("stations", {}):
		out[str(function)] = true
	return out

## Remove a placed station from YOUR plot: frees the node, clears the
## slot, and REFUNDS the dwelling item to the bag (a placed thing is
## yours to take back -- unlike the guard, who was paid in gold).
func remove_station(player, plot_id: String, function: String) -> Dictionary:
	if player == null or not ("entity_id" in player):
		return {"ok": false, "reason": "invalid_player"}
	var pid := str(player.entity_id)
	var plot: Dictionary = _plots.get(plot_id, {})
	if plot.is_empty():
		return {"ok": false, "reason": "unknown_plot"}
	if str(plot["owner_id"]) != pid:
		return {"ok": false, "reason": "not_owner"}
	var stations: Dictionary = plot.get("stations", {})
	if not stations.has(function):
		return {"ok": false, "reason": "not_placed"}
	var entry: Dictionary = stations[function]
	var node_id := str(entry.get("node_id", ""))
	var parent: Node = get_tree().current_scene if is_inside_tree() else null
	if parent != null:
		var node = parent.get_node_or_null(node_id)
		if node != null and is_instance_valid(node):
			node.queue_free()
	stations.erase(function)
	# Refund the dwelling item (placed from the PURSE in Item shape,
	# so it returns in Item shape through get_item).
	var ds = _svc("DataService")
	var inv_svc2 = _svc("InventoryService")
	var bag2 = inv_svc2.get_inventory(pid) if inv_svc2 != null and inv_svc2.has_method("get_inventory") else null
	var dwelling_id := str(entry.get("dwelling_id", ""))
	var as_item = ds.get_item(dwelling_id) if ds != null and ds.has_method("get_item") else null
	if bag2 != null and as_item != null and bag2.has_method("add_item"):
		bag2.add_item(as_item, 1)
	object_removed.emit(pid, plot_id, "station", dwelling_id)
	GameLog.info("DwellingService: %s removed station %s from plot %s" % [pid, function, plot_id])
	return {"ok": true}

## The placed station's world node: a simple pedestal; visuals upgrade
## later, the INTERACTION is what's load-bearing (the node is what
## interaction resolution targets). Joins the "placed_stations" group
## so the E-key chain resolves it; named deterministically so
## remove_station can find it after a save/reload. Each extra station
## offsets 1.5 m on X from the plot center so two stations in one hall
## never coincide (the nearest-node law would tie) and never overlap.
func _build_station_node(dwelling_id: String, function: String, slot_index: int = 0) -> StaticBody3D:
	var node := StaticBody3D.new()
	node.name = "station_%s_%d" % [function, Time.get_ticks_msec()]
	node.set_meta("dwelling_id", dwelling_id)
	node.set_meta("provides_function", function)
	node.add_to_group("placed_stations")
	node.position = Vector3(float(slot_index) * 1.5, 0, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	node.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	# Forge/anvil get smithy charcoal; the rest get carpenter oak.
	mat.albedo_color = Color(0.25, 0.22, 0.2) if function == "blacksmith" or function == "crafting_forge" else Color(0.55, 0.38, 0.22)
	box_mesh.material = mat
	mesh.mesh = box_mesh
	node.add_child(mesh)
	return node


## The E-key resolve: the nearest placed station within interaction
## radius of the player (the node's own item data carries the radius
## law; default 1.5 m matches every .tres). Returns {ok, node,
## function, dwelling_id, interaction_type} or {ok: false} -- the ONE
## resolving door for `_use_nearby_station` in PlayerController, so
## the walk-up-and-press law never re-derives from position guesses
## or a second meta read.
func resolve_nearby_station(player, max_radius: float = -1.0) -> Dictionary:
	if player == null or not ("global_position" in player):
		return {"ok": false}
	var origin: Vector3 = player.global_position
	var best: Node = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("placed_stations"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		# Radius law from the node's own dwelling data (the .tres truth).
		var dwelling_id := str(node.get_meta("dwelling_id", ""))
		var ds = _svc("DataService")
		var item = ds.get_item(dwelling_id) if ds != null and ds.has_method("get_item") else null
		var radius := 1.5
		if item != null:
			# Typed Item: one-arg Object.get + null-coalesce (the
			# established law; the two-arg Variant form throws here).
			var r_raw = item.get("interaction_radius")
			if r_raw != null and float(r_raw) > 0.0:
				radius = float(r_raw)
		if max_radius > 0.0:
			radius = minf(radius, max_radius)
		var dist: float = (node as Node3D).global_position.distance_to(origin)
		if dist <= radius and dist < best_dist:
			best_dist = dist
			best = node
	if best == null:
		return {"ok": false}
	return {
		"ok": true,
		"node": best,
		"function": str(best.get_meta("provides_function", "")),
		"dwelling_id": str(best.get_meta("dwelling_id", "")),
		"interaction_type": "craft",  # refined below by the caller if needed
	}

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
	# ADD the node's own local offset (stations slot 1.5 m apart on X;
	# a bare overwrite used to stack every station on the same tile,
	# which tied the nearest-node law). The offset was composed by the
	# builder; here it lands relative to the plot center.
	node.position = plot["center"] + node.position
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
		"dismissguard":
			return _cmd_dismiss_guard(sender_id, player, pos)
		"buildhouse":
			return _cmd_build_house(sender_id, player, pos)
		"placestation":
			return _cmd_place_station(sender_id, player, pos, args)
		"removestation":
			return _cmd_remove_station(sender_id, player, pos)
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
			var stations: Dictionary = plot.get("stations", {})
			if not stations.is_empty():
				desc += " | stations: " + ", ".join(stations.keys())
			_notify(sender_id, desc)
			return true
		_:
			return false

## /placestation <dwelling_id>: place a FUNCTIONAL dwelling (anvil,
## forge, workbench, cauldron) on YOUR plot. The item is consumed from
## the purse; the interaction then opens the craft/repair UI at that
## station (same gate as an NPC bench).
func _cmd_place_station(sender_id: String, player, pos: Vector3, args: Array) -> bool:
	var plot := get_nearest_plot(pos, "owned")
	if plot.is_empty() or str(plot["owner_id"]) != sender_id:
		_notify(sender_id, "You must stand on your own plot.")
		return true
	if args.is_empty() or str(args[0]).strip_edges().is_empty():
		_notify(sender_id, "Usage: placestation <dwelling_id>")
		return true
	var dwelling_id := str(args[0]).strip_edges()
	var result := place_station(player, str(plot["id"]), dwelling_id)
	if result.get("ok", false):
		_notify(sender_id, "%s placed. %s your hall now hosts it." % [dwelling_id, str(result.get("function", ""))])
	else:
		var why := str(result.get("reason", "failed"))
		var friendly: Dictionary = {
			"unknown_dwelling": "No such dwelling: %s" % dwelling_id,
			"not_a_station": "%s is not a functional station." % dwelling_id,
			"station_slot_taken": "This plot already hosts that kind of station.",
			"item_not_in_bag": "You are not carrying a %s." % dwelling_id,
		}
		_notify(sender_id, str(friendly.get(why, "Place failed: %s." % why)))
	return true

## /removestation <function>: take a placed station back (item
## refunded to the purse).
func _cmd_remove_station(sender_id: String, player, pos: Vector3) -> bool:
	var plot := get_nearest_plot(pos, "owned")
	if plot.is_empty() or str(plot["owner_id"]) != sender_id:
		_notify(sender_id, "You must stand on your own plot.")
		return true
	var stations: Dictionary = plot.get("stations", {})
	if stations.is_empty():
		_notify(sender_id, "You have no stations here.")
		return true
	# Without args, remove the first station (a plot tends to host one).
	var function := str(stations.keys()[0])
	var result := remove_station(player, str(plot["id"]), function)
	if result.get("ok", false):
		_notify(sender_id, "%s station taken back (item refunded)." % function)
	else:
		_notify(sender_id, "Remove failed: %s." % str(result.get("reason", "failed")))
	return true

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

## Dismiss the house guard on YOUR plot: unregisters it from the
## EntityService, frees the node, clears the plot's guard slot. No
## refund (the guard was paid for; fair-weather employers eat the cost).
func _cmd_dismiss_guard(sender_id: String, player, pos: Vector3) -> bool:
	var plot := get_nearest_plot(pos, "owned")
	if plot.is_empty() or str(plot["owner_id"]) != sender_id:
		_notify(sender_id, "You must stand on your own plot.")
		return true
	var guard_id := str(plot.get("guard_id", ""))
	if guard_id == "":
		_notify(sender_id, "You have no house guard here.")
		return true
	var es = _svc("EntityService")
	var guard = null
	if es != null and es.has_method("get_entity"):
		guard = es.get_entity(guard_id)
	if guard == null or not is_instance_valid(guard):
		# Registry lost the node (scene reload): just clear the slot.
		plot["guard_id"] = ""
		_notify(sender_id, "Guard slot cleared.")
		return true
	if es != null and es.has_method("unregister_by_id"):
		es.unregister_by_id(guard_id, "dismissed")
	guard.queue_free()
	plot["guard_id"] = ""
	object_removed.emit(sender_id, str(plot["id"]), "guard", guard_id)
	_notify(sender_id, "House guard dismissed.")
	GameLog.info("DwellingService: %s dismissed house guard %s on plot %s" % [sender_id, guard_id, str(plot["id"])])
	return true

## ------------------------------------------------------------------
## THE HOUSE ITSELF: a 3D structure you can walk into.
## ------------------------------------------------------------------

## Build a wooden house on the plot: floor, four walls with a doorway
## gap (front), and a gabled roof, all with StaticBody collision so the
## player physically enters and exists inside. The plot's house_id is
## stamped; one house per plot.
func build_house(player, plot_id: String) -> Dictionary:
	if player == null or not ("entity_id" in player):
		return {"ok": false, "reason": "invalid_player"}
	var pid := str(player.entity_id)
	var plot: Dictionary = _plots.get(plot_id, {})
	if plot.is_empty():
		return {"ok": false, "reason": "unknown_plot"}
	if str(plot["owner_id"]) != pid:
		return {"ok": false, "reason": "not_owner"}
	if str(plot.get("house_id", "")) != "":
		return {"ok": false, "reason": "already_built"}
	if not _spend_gold(player, HOUSE_COST):
		return {"ok": false, "reason": "insufficient_gold"}

	var house := _build_house_node(str(plot["id"]), plot["center"])
	if not _spawn_at(house, plot):
		house.queue_free()
		return {"ok": false, "reason": "spawn_failed"}
	plot["house_id"] = house.name
	house_built.emit(pid, plot_id, house.name)
	GameLog.info("DwellingService: %s built a house on plot %s (%d gold)" % [pid, plot_id, HOUSE_COST])
	return {"ok": true, "house_id": house.name}


## Construct the structure node. Geometry: a 6x6m footprint, 3m walls,
## doorway gap (1.4m wide) centered on the +Z wall, gabled roof. Every
## piece is a StaticBody3D + CollisionShape3D + MeshInstance3D so the
## player can walk in but not through walls.
func _build_house_node(house_id: String, center: Vector3) -> StaticBody3D:
	var house := StaticBody3D.new()
	house.name = "house_%s" % house_id

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.22)  # plank brown
	var darker := StandardMaterial3D.new()
	darker.albedo_color = Color(0.42, 0.28, 0.16)  # beam brown

	var parts: Array = [
		# [size, center-y from ground, material]
		[Vector3(6.0, 0.2, 6.0), 0.1, wood],    # floor
		[Vector3(6.0, 3.0, 0.2), 1.7, wood],    # back wall (-Z)
		[Vector3(0.2, 3.0, 6.0), 1.7, wood],    # left wall (-X)
		[Vector3(0.2, 3.0, 6.0), 1.7, wood],    # right wall (+X)
		[Vector3(2.3, 3.0, 0.2), 1.7, wood],    # front wall left of door
		[Vector3(2.3, 3.0, 0.2), 1.7, wood],    # front wall right of door
		[Vector3(1.4, 0.8, 0.2), 2.6, wood],    # door lintel (above the 2.2m gap)
	]
	var offsets: Array = [
		Vector3(0, 0, 0),
		Vector3(0, 0, -2.9),
		Vector3(-2.9, 0, 0),
		Vector3(2.9, 0, 0),
		Vector3(-1.85, 0, 2.9),
		Vector3(1.85, 0, 2.9),
		Vector3(0, 0, 2.9),
	]
	for i in parts.size():
		var size: Vector3 = parts[i][0]
		var piece := StaticBody3D.new()
		piece.name = "piece_%d" % i
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		piece.add_child(shape)
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		box_mesh.material = parts[i][2]
		mesh.mesh = box_mesh
		piece.add_child(mesh)
		house.add_child(piece)
		# Position: x/z from the layout, y = the piece's own center height.
		piece.position = Vector3(offsets[i].x, float(parts[i][1]), offsets[i].z)

	# Gabled roof: two slabs meeting at a ridge, no collision interior
	# issues since the player is below them.
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.35, 0.2, 0.14)  # shingle brown
	for side in [-1.0, 1.0]:
		var slab := StaticBody3D.new()
		slab.name = "roof_%s" % ("neg" if side < 0 else "pos")
		var rshape := CollisionShape3D.new()
		var rbox := BoxShape3D.new()
		rbox.size = Vector3(3.6, 0.15, 6.6)
		rshape.shape = rbox
		slab.add_child(rshape)
		var rmesh := MeshInstance3D.new()
		var rmesh_box := BoxMesh.new()
		rmesh_box.size = Vector3(3.6, 0.15, 6.6)
		rmesh_box.material = roof_mat
		rmesh.mesh = rmesh_box
		slab.add_child(rmesh)
		slab.rotation = Vector3(0, 0, side * 0.5)  # ~30 degrees pitch
		slab.position = Vector3(side * 1.55, 3.85, 0)
		house.add_child(slab)
	return house


func _cmd_build_house(sender_id: String, player, pos: Vector3) -> bool:
	var plot := get_nearest_plot(pos, "owned")
	if plot.is_empty() or str(plot["owner_id"]) != sender_id:
		_notify(sender_id, "You must stand on your own plot to build.")
		return true
	var result := build_house(player, str(plot["id"]))
	if result["ok"]:
		_notify(sender_id, "House built! Your home stands at last.")
	else:
		var why := str(result["reason"])
		if why == "already_built":
			_notify(sender_id, "You already have a house here.")
		elif why == "insufficient_gold":
			_notify(sender_id, "Not enough gold (%d needed)." % HOUSE_COST)
		else:
			_notify(sender_id, "Build failed: %s." % why)
	return true

## Player feedback. NotificationService may be absent in script mode.
func _notify(player_id: String, message: String) -> void:
	var ns = _svc("NotificationService")
	if ns != null and ns.has_method("notify"):
		ns.notify(NotifKind.AUTO_ACTION, message, "DwellingService",
			"dwelling:%s:%s" % [player_id, message.hash()], {}, player_id)
	else:
		GameLog.info("DwellingService [%s]: %s" % [player_id, message])
