extends SceneTree

## Probe: THE BANKER GATE (2026-10-15). The vault is a place, not a
## global hotkey: bank opens only within BANKER_RADIUS of a banker NPC
## (NPCData.has_offering("bank") -- the same read the action menu uses).
## Pins: gate refuses far & empty, allows near, re-refuses when the
## player walks away, and the action-menu arm attaches the walk-away
## close to the vault panel.

var _fails: int = 0

func _check(label: String, cond: bool) -> void:
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Data truth first: the banker resources carry a "bank" offering.
	var ds = root.get_node_or_null("DataService")
	var banker_data = ds.get_npc("npc_banker_village") if ds and ds.has_method("get_npc") else null
	if banker_data == null:
		banker_data = load("res://data/npc/npc_banker_village.tres")
	_check("the village banker carries a bank offering (data truth)", \
		banker_data != null and banker_data.has_method("has_offering") \
		and banker_data.has_offering("bank"))

	# Gate law with a live MenuManager + player + banker entity.
	var MM = load("res://ui/components/menu_manager.gd")
	var mm: Node = MM.new()
	root.add_child(mm)
	await process_frame

	var pm = root.get_node_or_null("PlayerManager")
	var PlayerScript = load("res://entities/player/player_base.gd")
	var player = PlayerScript.new()
	player.entity_id = "bank_probe_player"
	if pm:
		pm.local_player = player
	root.add_child(player)
	await process_frame

	_check("gate refuses when no banker is nearby", not bool(mm.call("_banker_gate", Vector3.ZERO)))

	# A banker NPC inside the radius passes (offering-npcs law shape).
	var NPCEntity = load("res://core/entities/npc_entity.gd")
	var banker = NPCEntity.new()
	banker.npc_data = banker_data
	banker.entity_id = "npc_bank_probe"
	if "entity_type" in banker:
		pass
	root.add_child(banker)
	await process_frame
	var es = root.get_node_or_null("EntityService")
	if es and es.has_method("register_entity"):
		es.register_entity(banker, null, "npc_bank_probe")

	player.global_position = Vector3(0, 0, 0)
	await process_frame
	_check("gate allows when a banker stands nearby", bool(mm.call("_banker_gate", Vector3.ZERO)))

	# Walk past the radius: refuse again.
	player.global_position = Vector3(40, 0, 0)
	await process_frame
	_check("gate refuses past the banker radius (no bank-from-anywhere)", \
		not bool(mm.call("_banker_gate", Vector3.ZERO)))

	# Walk-away close: the bank panel inherits the canonical 12m when
	# opened from an NPC arm (menu_manager attaches via set_npc_proximity).
	var panel = mm._get_panel("bank")
	_check("the MenuManager bank panel exists", panel != null)
	if panel != null:
		_check("the vault panel carries the NPC-attach law", "set_npc_proximity" in panel)
		_check("the vault panel rides the canonical 12m radius", \
			float(panel.get("_max_interact_distance")) == 12.0)
		panel.call("set_npc_proximity", Vector3.ZERO)
		_check("attach arms the proximity law", bool(panel.get("_proximity_enabled")))

	if is_instance_valid(mm):
		mm.queue_free()

	print("BANKER GATE probe: %d failure(s)" % _fails)
	quit(0 if _fails == 0 else 1)
