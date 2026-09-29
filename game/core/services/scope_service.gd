## ScopeService - the S12 visual scene swap (prd-social-instances.md).
##
## The player is a direct child of the globe scene with RADIAL gravity
## math (globe_player.gd). Instance rooms are PLANAR AABB worlds (the
## InstanceContract). Both truths are load-bearing, so instead of a
## full scene reload the swap REPARENTS the player node between
## scopes and flips one flag:
##
##   enter_scope  : player -> instance room root, planar_mode = true,
##                  gravity yields to the contract. Camera rides along
##                  (it is a child of the player, so no retargeting).
##   exit_scope   : player -> globe world_root, planar_mode = false,
##                  radial math resumes exactly where it left off.
##   spectate     : same room scope, but input is severed (a spectator
##                  is a camera, not a fighter) and the room's
##                  spectator book records them for permission checks.
##   world:<id>   : the S16.3 world scope (prd-multiworld.md sec 3).
##                  Same reparent seam, one more scope: the player
##                  renders under another world's globe root with
##                  RADIAL math (planar_mode stays false -- every
##                  world is a globe). The Moon Gate requests the
##                  transit; this service performs and remembers it.
##                  Boot state stays "globe" (= conceptually
##                  world:main) so pre-multiworld behavior is
##                  untouched. The entry law is enforced here: the
##                  registry's is_enterable() gates every swap (the
##                  underworld's scope simply cannot be entered), and
##                  force=true is the DEV_ONLY probe hatch (S16.6).
##
## The teleport itself stays BoutTeleportService's job (position is
## authoritative; this service owns RENDERING scope). Autoload: NO
## class_name (AGENTS rule).
extends Node

const Contract = preload("res://core/schemas/instance_contract.gd")
const WorldRegistryScript = preload("res://core/frame/srv/world_registry.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## player_id -> "globe" | "bout:<instance_id>" | "spectate:<instance_id>"
var _scopes: Dictionary = {}
## player_id -> the Node the player escaped FROM when entering a room
## scope. The room-closed safety net reparents them back here -- a
## freed room must never take the player with it.
var _escape: Dictionary = {}
## Lazy world registry (S16.1 lattice) for the entry law.
var _worlds: Object = null


func _ready() -> void:
	if ArenaRoomService != null and ArenaRoomService.has_signal("room_closed"):
		ArenaRoomService.room_closed.connect(_on_room_closed)
	GameLog.info("ScopeService: Ready (rendering scopes)")


## Where does this player currently render?
func scope_of(player_id: String) -> String:
	return str(_scopes.get(player_id, "globe"))


func is_in_bout_scope(player_id: String) -> bool:
	return str(_scopes.get(player_id, "globe")).begins_with("bout:")


func is_spectating(player_id: String) -> bool:
	return str(_scopes.get(player_id, "globe")).begins_with("spectate:")


# ------------------------------------------------------------------
# World scopes (S16.3, prd-multiworld.md sec 3)
# ------------------------------------------------------------------

## Which world does this player currently render on? "globe" (the
## boot state) and bout/spectate scopes all mean the main world.
func world_of(player_id: String) -> String:
	var scope := scope_of(player_id)
	if scope.begins_with("world:"):
		return scope.trim_prefix("world:")
	return "main"


## True when the player renders under a NON-main world's root.
func is_off_world(player_id: String) -> bool:
	return world_of(player_id) != "main"


## The world's declaration, or null for unknown ids. Loads the lattice
## lazily so script-mode probes and boot both pay the same cheap price.
func world_data(world_id: String):
	if _worlds == null:
		_worlds = WorldRegistryScript.new()
		_worlds.load_worlds()
	return _worlds.get_world(world_id)


## The Moon Gate's transit. Reparents the player under the target
## world's globe root and records the world scope. The registry's
## entry law is authoritative: OFFLINE/DEV_ONLY worlds refuse unless
## force=true (the S16.6 dev hatch). No planar flip -- radial gravity
## math is the same truth on every globe.
func enter_world_scope(player_id: String, world_id: String, world_root: Node3D, force: bool = false) -> bool:
	return _swap_world(player_id, world_id, world_root, force, true)


## Return transit: leave one world's scope for another world's root
## (the Moon Gate's ride home names "main"). Same law, same seam.
func exit_to_world(player_id: String, world_id: String, world_root: Node3D, force: bool = false) -> bool:
	return _swap_world(player_id, world_id, world_root, force, false)


func _swap_world(player_id: String, world_id: String, world_root: Node3D, force: bool, entering: bool) -> bool:
	var pid := _resolve_player_id(player_id)
	if pid == "":
		return false
	var world = world_data(world_id)
	if world == null:
		return false
	if not force and not world.is_enterable():
		GameLog.warn("ScopeService: world %s refused (offline law) for %s" % [world_id, pid])
		return false
	var player = _player_node(pid)
	if player == null:
		return false
	# A transit without a destination root would strand the player in a
	# scope with no node to render under -- refuse instead.
	if world_root == null or not is_instance_valid(world_root):
		GameLog.warn("ScopeService: no world root for %s, transit aborted" % world_id)
		return false
	var parent: Node = player.get_parent()
	# Room-style escape capture only on the FIRST hop out of the main
	# world: a world-to-world swap must never strand the player on a
	# root that a room teardown could free underneath them.
	if parent != null and not is_off_world(pid):
		if not _escape.has(pid):
			_escape[pid] = parent
	if parent != null and is_instance_valid(parent):
		parent.remove_child(player)
	world_root.add_child(player)
	player.set("planar_mode", false)
	_scopes[pid] = "world:%s" % world_id
	if NotificationService != null:
		NotificationService.notify(
			NotifKind.CUSTOM,
			"%s %s" % ["You arrive on" if entering else "You return to", str(world.display_name)],
			"ScopeService",
			"world:transit:%s:%s" % [pid, world_id],
			{"world": world_id, "entering": entering}
		)
	return true


## Move a player into a room's scope. room_root is the ArenaInstance
## node; the player node is reparented under it (rendering + physics
## scope flip together). The pre-swap parent is remembered as the
## escape hatch. Returns true on a real swap.
func enter_room_scope(player_id: String, room_root: Node3D) -> bool:
	var player = _player_node(player_id)
	if player == null or room_root == null:
		return false
	var parent: Node = player.get_parent()
	if parent != null:
		if not _escape.has(player_id):
			_escape[player_id] = parent
		parent.remove_child(player)
	room_root.add_child(player)
	player.set("planar_mode", true)
	_scopes[player_id] = "bout:%s" % str(room_root.get("instance_id"))
	return true


## Spectator scope: same room, input severed. The player keeps
## rendering (their avatar sits at the rim as a viewing body) but
## move intent is zeroed by planar_mode + spectate flag on the body.
func enter_spectate_scope(player_id: String, room_root: Node3D) -> bool:
	var ok: bool = enter_room_scope(player_id, room_root)
	if ok:
		_scopes[player_id] = "spectate:%s" % str(room_root.get("instance_id"))
		var spectator = _player_node(player_id)
		if spectator != null:
			spectator.set("planar_mode", true)
	return ok


## Back to the globe. globe_root is the scene's world_root; when the
## caller cannot resolve one (script mode, headless), the remembered
## escape parent is used -- the swap must never strand a player in a
## node that is about to be freed. Radial math resumes (planar_mode =
## false restores the globe path verbatim).
func exit_to_globe(player_id: String, globe_root: Node3D) -> bool:
	var player = _player_node(player_id)
	if player == null:
		return false
	var target: Node = globe_root
	if target == null or not is_instance_valid(target):
		target = _escape.get(player_id)
	if target == null or not is_instance_valid(target):
		return false
	var parent: Node = player.get_parent()
	if parent != null and is_instance_valid(parent):
		parent.remove_child(player)
	target.add_child(player)
	player.set("planar_mode", false)
	_scopes[player_id] = "globe"
	_escape.erase(player_id)
	return true


## Room closed under a player: PHYSICALLY rescue them back to their
## escape parent (a queue_free'd room would free a reparented player
## with it), then reset the scope. This is the safety net for teardown
## paths that never ran an explicit exit_to_globe.
func _on_room_closed(instance_id: String, _room) -> void:
	for pid in _scopes.keys():
		var scope: String = str(_scopes[pid])
		if scope == "bout:%s" % instance_id or scope == "spectate:%s" % instance_id:
			var player = _player_node(str(pid))
			if player != null and is_instance_valid(player):
				var target = _escape.get(str(pid))
				if target != null and is_instance_valid(target):
					var parent: Node = player.get_parent()
					if parent != null and is_instance_valid(parent):
						parent.remove_child(player)
					target.add_child(player)
				player.set("planar_mode", false)
			_escape.erase(str(pid))
			_scopes[pid] = "globe"
			GameLog.warn("ScopeService: %s rescued from closed room %s" % [str(pid), instance_id])


## Resolve the local player's node by entity id (PlayerManager's
## local_player first, EntityService fallback). Empty id = the local
## player (the gate interaction has no server-side id on the client).
func _resolve_player_id(player_id: String) -> String:
	if player_id != "":
		return player_id
	var pm = _player_manager()
	if pm != null:
		var local = pm.get("local_player")
		if local != null and is_instance_valid(local) and "entity_id" in local:
			return str(local.entity_id)
	return ""

func _player_node(player_id: String):
	var pm = _player_manager()
	if pm != null:
		var local = pm.get("local_player")
		if local != null and is_instance_valid(local) and "entity_id" in local \
				and str(local.entity_id) == player_id:
			return local
	var esvc = _entity_service()
	if esvc != null:
		return esvc.get_entity(player_id)
	return null


func _player_manager():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("PlayerManager")


func _entity_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("EntityService")
