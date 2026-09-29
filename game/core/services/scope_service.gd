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
##
## The teleport itself stays BoutTeleportService's job (position is
## authoritative; this service owns RENDERING scope). Autoload: NO
## class_name (AGENTS rule).
extends Node

const Contract = preload("res://core/schemas/instance_contract.gd")

## player_id -> "globe" | "bout:<instance_id>" | "spectate:<instance_id>"
var _scopes: Dictionary = {}
## player_id -> the Node the player escaped FROM when entering a room
## scope. The room-closed safety net reparents them back here -- a
## freed room must never take the player with it.
var _escape: Dictionary = {}


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
## local_player first, EntityService fallback).
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
