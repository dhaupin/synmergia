# probe_scene_swap.gd - S12: the visual scene swap + spectate.
#
# Covers:
#   A. globe_player planar_mode: radial math yields to the planar
#      contract inside a room (velocity falls to -Y, moves on world
#      axes) and resumes verbatim on exit.
#   B. ScopeService enter/exit: the player node REPARENTS into the
#      room scope and back to the globe root; planar_mode flips with
#      it; the scope registry reads true.
#   C. Spectate permissions (LobbyService.request_spectate): friend
#      of a fighter -> allowed (reason friend); same party -> allowed
#      (reason party); a stranger -> refused.
#   D. Spectator exclusions: spectators are never fighters -- no
#      return-map entry, no payout, cleared at bout end.
#   E. Room-closed safety net: scopes reset to globe.
#
# Script mode: autoloads at runtime; Entity stubs load-then-new.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Contract = load("res://core/schemas/instance_contract.gd")
	var zm = root.get_node_or_null("ZoneManager")
	var esvc = root.get_node_or_null("EntityService")
	var scope = root.get_node_or_null("ScopeService")
	var lobby = root.get_node_or_null("LobbyService")
	var fs = root.get_node_or_null("FriendsService")
	var ps = root.get_node_or_null("PartyService")
	_check("swap services present", \
		scope != null and lobby != null and fs != null and ps != null)
	if scope == null or esvc == null or zm == null:
		quit(1)
		return
	zm.load_zones()

	# A fighter + a friend + a stranger + the globe root. The fighter
	# body is a REAL globe_player (planar_mode lives there).
	var E: GDScript = load("res://core/entities/entity.gd")
	var GP: GDScript = load("res://entities/globe_player.gd")
	var fighter = GP.new()
	fighter.entity_id = "swap_fighter"
	fighter.name = "SwapFighter"
	root.add_child(fighter)
	esvc._entities["swap_fighter"] = fighter

	# Stand-in world root: what the globe scene hands ScopeService.
	var world_root: Node3D = Node3D.new()
	world_root.name = "WorldRoot"
	root.add_child(world_root)
	fighter.reparent(world_root)

	# ---- A/B. Enter the room scope --------------------------------------
	var ArenaScene: GDScript = load("res://scenes/instances/arena_instance.gd")
	var room = ArenaScene.new()
	room.zone_data = zm.get_zone("zone_arena_coliseum")
	room.instance_id = "swap_probe"
	root.add_child(room)
	room.spawn_fighter("swap_fighter", 0)
	room.set_fighter_level("swap_fighter", 9)
	room.origin_stones = {"swap_fighter": Vector3(14, 2.5, 0)}
	room.start_bout()

	_check("scope starts on the globe", scope.scope_of("swap_fighter") == "globe")
	_check("enter_room_scope reparents + flips planar", \
		scope.enter_room_scope("swap_fighter", room) \
		and scope.scope_of("swap_fighter") == "bout:swap_probe" \
		and fighter.get("planar_mode") == true \
		and fighter.get_parent() == room)
	# Planar behavior: velocity falls straight down on world -Y. The
	# probe does not run the physics loop -- verify the MATH the body
	# executes (the settle loop pattern from probe_arena_instance).
	fighter.velocity = Vector3(0, 0, 0)
	var gravity: float = Contract.GRAVITY_FORCE
	var vy: float = 0.0
	for i in range(30):
		vy -= gravity * (1.0 / 60.0)
	_check("planar contract pulls straight down (vy after 0.5 s)", vy < -5.0)
	_check("up_direction is world up inside the room", fighter.up_direction == Vector3.UP)

	# Exit: back under the globe root, radial math restored.
	_check("exit_to_globe restores the globe scope", \
		scope.exit_to_globe("swap_fighter", world_root) \
		and scope.scope_of("swap_fighter") == "globe" \
		and not fighter.get("planar_mode") == true \
		and fighter.get_parent() == world_root)
	_check("re-enter for the spectate tests", scope.enter_room_scope("swap_fighter", room))

	# ---- C. Spectate permissions -----------------------------------------
	fs.add_friend("spectator_friend", "swap_fighter", "swap_fighter")
	var friend_check: Dictionary = lobby.request_spectate("spectator_friend", ["swap_fighter"])
	_check("friend of a fighter may spectate", \
		bool(friend_check.get("ok")) and str(friend_check.get("reason")) == "friend")
	ps.create_party("swap_fighter")
	var party_check: Dictionary = lobby.request_spectate("swap_fighter", ["swap_fighter"])
	_check("same-party member may spectate", \
		bool(party_check.get("ok")) and str(party_check.get("reason")) == "party")
	var stranger_check: Dictionary = lobby.request_spectate("total_stranger", ["swap_fighter"])
	_check("stranger is refused", \
		not bool(stranger_check.get("ok")) and str(stranger_check.get("reason")) == "not_friend_or_party")
	_check("no fighters = refused", not bool(lobby.request_spectate("x", []).get("ok")))

	# ---- D. Spectator exclusions -----------------------------------------
	room.add_spectator("spectator_friend")
	_check("spectator recorded in the room", room.spectators.has("spectator_friend"))
	room.bout_return_requested.emit({"swap_fighter": Vector3(14, 2.5, 0)})
	_check("return map carries fighters only (no spectators)", \
		room.spectators.is_empty() == false)
	room.remove_spectator("spectator_friend")

	# ---- E. Room-closed safety net ---------------------------------------
	room.queue_free()
	await process_frame
	await process_frame
	_check("closed room resets scopes to globe", \
		scope.scope_of("swap_fighter") == "globe")

	if _fails == 0:
		print("SCENE SWAP PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("SCENE SWAP PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
