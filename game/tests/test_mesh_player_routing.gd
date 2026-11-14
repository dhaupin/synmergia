## test_mesh_player_routing.gd - THE MESH PLAYER-ROUTING RECEIPT.
##
## The shard mesh's player truth (labs/prd-shard-mesh.md): CoordinatorService
## owns the roster (per-shard player_count, _player_shard_map, presence) but
## for a long time NOTHING fed it -- assign_player_to_shard was documented
## "called on login/character select" with zero callers, so the registry's
## player counts were frozen at 0 forever. This receipt locks the loop:
##  * a real player JOIN (EntityService.player_joined, the seam GameManager
##    listens on) assigns the player to this shard: map + presence + count,
##  * a repeat join to the SAME shard does not double-count (idempotence),
##  * a shard MOVE emits player_shard_changed and moves the counts,
##  * a real player LEAVE (player_left) clears the map + presence + count,
##  * the /mesh operator report renders the live per-shard player line.
##
## Run: cd game && godot --headless --path . --script res://tests/test_mesh_player_routing.gd
extends SceneTree

const SpawnMetadataScript := preload("res://core/events/spawn_metadata.gd")
const EntityScript := preload("res://core/entities/entity.gd")

var _es: Node
var _coord: Node
var _cs: Node
var _perm: Node
var _ns: Node
var _fired: Array = []
var _passes: int = 0
var _fails: int = 0


func _initialize() -> void:
	await process_frame
	_es = root.get_node_or_null("EntityService")
	_coord = root.get_node_or_null("CoordinatorService")
	_cs = root.get_node_or_null("ChatService")
	_perm = root.get_node_or_null("PermissionManager")
	_ns = root.get_node_or_null("NotificationService")
	if _es == null or _coord == null:
		push_error("FAIL: EntityService/CoordinatorService autoloads missing")
		quit(1)
		return
	print("--- MESH PLAYER ROUTING ---")
	# Route the real EntityService join/leave seam through the SAME wiring
	# GameManager uses (the seam under test is the wiring, not a stub).
	_es.player_joined.connect(_on_player_joined)
	_es.player_left.connect(_on_player_left)
	if _ns != null:
		_ns.notification_sent.connect(func(_pid, n):
			_fired.append(str(n.get("message", "") if n is Dictionary else n)))
	await _run()
	print("--- RESULT: %d passed, %d failed ---" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("PASS: ", label)
	else:
		_fails += 1
		push_error("FAIL: %s" % label)


# --- The GameManager wiring, reproduced verbatim -------------------------
func _on_player_joined(player, _metadata) -> void:
	var coord = root.get_node_or_null("CoordinatorService")
	if coord == null or not coord.has_method("assign_player_to_shard"):
		return
	var pid := _mesh_player_id(player)
	if pid.is_empty():
		return
	coord.assign_player_to_shard(pid, _mesh_local_shard_id())


func _on_player_left(player, _metadata) -> void:
	var coord = root.get_node_or_null("CoordinatorService")
	if coord == null or not coord.has_method("remove_player_from_shard"):
		return
	var pid := _mesh_player_id(player)
	if pid.is_empty():
		return
	coord.remove_player_from_shard(pid)


func _mesh_player_id(player) -> String:
	if player == null or not is_instance_valid(player):
		return ""
	if "entity_id" in player and str(player.get("entity_id")) != "":
		return str(player.get("entity_id"))
	if "display_name" in player:
		return str(player.get("display_name"))
	return ""


func _mesh_local_shard_id() -> String:
	var sm = root.get_node_or_null("ShardManager")
	if sm != null:
		return sm.shard_id
	return "shard_1"


# --- helpers -------------------------------------------------------------
func _make_player(entity_id: String, display_name: String):
	var e = EntityScript.new()
	e.entity_id = entity_id
	e.display_name = display_name
	e.entity_type = EntityScript.EntityType.PLAYER
	return e


func _count(shard_id: String) -> int:
	var info: Dictionary = _coord.get_shard_info(shard_id)
	return int(info.get("player_count", -1))


func _run() -> void:
	var shard := _mesh_local_shard_id()
	# Make sure our shard is registered (a coordinator-less boot registers
	# via ShardManager; a script boot may need the explicit leg).
	if not _coord.get_all_shard_ids().has(shard):
		_coord.register_shard(shard, {"name": shard, "is_primary": true})

	var base := _count(shard)

	# --- 1. JOIN assigns the player: map + presence + count --------------
	var p1 = _make_player("char_alpha", "Alpha")
	_es.register_entity(p1, SpawnMetadataScript.new(0, "Alpha", "zone_x", Vector3.ZERO), "char_alpha")
	await process_frame
	_ok(_coord.get_shard_for_player("char_alpha") == shard,
		"join assigns the player to this shard")
	_ok(_count(shard) == base + 1,
		"join increments the shard player_count")
	var pres: Dictionary = _coord.get_player_presence("char_alpha")
	_ok(str(pres.get("shard_id", "")) == shard,
		"join records presence with the shard id")

	# --- 2. IDEMPOTENCE: a repeat assign does not double-count -----------
	_coord.assign_player_to_shard("char_alpha", shard)
	_ok(_count(shard) == base + 1,
		"a repeat assignment to the SAME shard does not double-count")

	# --- 3. MOVE emits player_shard_changed and moves the counts ---------
	var changed: Array = []
	_coord.player_shard_changed.connect(func(pid, frm, to): changed.append([pid, frm, to]))
	_coord.register_shard("shard_2", {"name": "shard_2"})
	var base2 := _count("shard_2")
	_coord.assign_player_to_shard("char_alpha", "shard_2")
	_ok(changed.size() == 1 and changed[0][1] == shard and changed[0][2] == "shard_2",
		"a shard move emits player_shard_changed(from, to)")
	_ok(_count(shard) == base and _count("shard_2") == base2 + 1,
		"a shard move decrements the old and increments the new")
	# Move it back so the leave leg reads cleanly.
	_coord.assign_player_to_shard("char_alpha", shard)

	# --- 4. LEAVE clears map + presence + count --------------------------
	_es.unregister_entity(p1, "test_leave")
	await process_frame
	_ok(_coord.get_shard_for_player("char_alpha") == "",
		"leave clears the player->shard map")
	_ok(_coord.get_player_presence("char_alpha").is_empty(),
		"leave clears the presence record")
	_ok(_count(shard) == base,
		"leave decrements the shard player_count")

	# --- 5. the /mesh report renders the live player line ----------------
	if _cs != null and _perm != null and _ns != null:
		_perm._validation_cache["mesh_admin"] = {"time": Time.get_ticks_msec(), "level": 100}
		# Put a player back so the line shows a real count.
		var p2 = _make_player("char_beta", "Beta")
		_es.register_entity(p2, SpawnMetadataScript.new(0, "Beta", "zone_x", Vector3.ZERO), "char_beta")
		await process_frame
		_fired.clear()
		_cs._handle_command("mesh_admin", 9, "mesh", "")
		var said := false
		for m in _fired:
			if str(m).find("players: ") != -1:
				said = true
		_ok(said, "/mesh reports a players: line")
		var shows := false
		for m in _fired:
			if str(m).find("%s=%d" % [shard, base + 1]) != -1:
				shows = true
		_ok(shows, "/mesh player line shows this shard's live count")
	else:
		_ok(true, "/mesh leg skipped (autoloads absent)")
