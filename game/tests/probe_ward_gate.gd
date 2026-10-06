# probe_ward_gate.gd - the hard gate: admin keys in one registry, the
# breach embargo in the same place (labs/prd-ward-gate.md).
#
# Covers:
#   A. The registry: gate_warden_keys loads, filename == id, the key
#      role is the reserved GM role (0), the Skywarden is the token
#      mount, and the embargo list ships EMPTY (a breach is an edit or
#      an API call, never shipped data).
#   B. Defense in depth: every key signal must match -- role truth
#      (server-side character class), the token mount in the Ride
#      ledger, the token items. Unknown rider = closed. Revoke the
#      key and the gate closes again.
#   C. The breach embargo: embargo_item/lift_embargo through the
#      runtime ledger (persisted, expiring), the registry branch, and
#      allow_drop as the one drop seam.
#   D. The loot seam: embargoed items never materialize as drops, and
#      a fully-embargoed drop spawns nothing.
#
# Script mode: autoloads resolved at runtime (WardGateService,
# RideService, DataService, LootService).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("PASS: ", label)
	else:
		_fails += 1
		print("FAIL: ", label)

func _run() -> void:
	var gate_svc = root.get_node_or_null("WardGateService")
	var rides = root.get_node_or_null("RideService")
	var ds = root.get_node_or_null("DataService")
	var loot = root.get_node_or_null("LootService")
	_check("WardGateService present", gate_svc != null)
	_check("RideService present", rides != null)
	_check("DataService present", ds != null)
	_check("LootService present (the drop seam)", loot != null)
	if gate_svc == null or rides == null or ds == null or loot == null:
		quit(1)
		return
	var WGD: GDScript = load("res://core/schemas/ward_gate_data.gd")
	var CCL: GDScript = load("res://core/schemas/character_class.gd")
	var CDS: GDScript = load("res://core/schemas/character_data.gd")
	var DS: GDScript = preload("res://adapters/persistence/dict_store.gd")
	var gm = root.get_node_or_null("GameManager")

	# ---- A. The registry -----------------------------------------------------
	var gate = ds.get_gate("gate_warden_keys")
	_check("the keyring registry loads (filename == id, the naming law)", \
		gate != null and str(gate.id) == "gate_warden_keys")
	_check("the key role is the reserved GM role (0, never via .tres)", \
		gate != null and int(gate.key_role) == int(CCL.Role.GM) and int(CCL.Role.GM) == 0)
	_check("the Skywarden is the token mount (the warden's key)", \
		gate != null and Array(gate.key_mounts).has("mount_gm_skywarden"))
	_check("the registry ships with an EMPTY embargo (a breach is an edit or a call)", \
		gate != null and Array(gate.embargoed_items).is_empty())
	_check("the registry names what it opens", \
		gate != null and not Array(gate.opens).is_empty())

	# ---- B. Defense in depth ----------------------------------------------------
	_check("an unknown rider is a CLOSED gate (fail-closed is the posture)", \
		not gate_svc.can_open("wg_nobody", "gate_warden_keys"))
	_check("an unknown gate id is closed (and warned)", \
		not gate_svc.can_open("wg_nobody", "gate_does_not_exist"))
	var plain = CDS.new("human", "human_warrior", "Plain Rider")
	if gm != null:
		gm.notify_player_entered_world("wg_plain", plain)
	_check("a non-warden's role truth keeps the gate closed", \
		not gate_svc.can_open("wg_plain", "gate_warden_keys"))
	var wcd = CDS.new("human", "gm_human", "Warden Probe")
	if gm != null:
		gm.notify_player_entered_world("wg_gm", wcd)
	_check("a warden enters the world: the Skywarden auto-answers, the gate OPENS", \
		rides.owns_mount("wg_gm", "mount_gm_skywarden") \
		and gate_svc.can_open("wg_gm", "gate_warden_keys"))
	_check("the mount leg alone: revoke the key, the gate closes again", \
		rides.revoke_mount("wg_gm", "mount_gm_skywarden") \
		and not gate_svc.can_open("wg_gm", "gate_warden_keys"))
	_check("the ledger forgives: the warden's key returns", \
		rides.grant_mount("wg_gm", "mount_gm_skywarden") \
		and gate_svc.can_open("wg_gm", "gate_warden_keys"))
	var item_gate = WGD.new()
	item_gate.id = "gate_probe_items"
	item_gate.key_role = 0
	var token_mounts: Array[String] = ["mount_gm_skywarden"]
	item_gate.key_mounts = token_mounts
	var token_items: Array[String] = ["item_quest_sealed_writ"]
	item_gate.key_items = token_items
	_check("the item leg: a warden without the token item is still CLOSED", \
		not gate_svc.gate_open_for("wg_gm", item_gate))
	var no_items: Array[String] = []
	item_gate.key_items = no_items
	_check("every leg matching: the in-memory gate opens for the warden", \
		gate_svc.gate_open_for("wg_gm", item_gate))

	# ---- C. The breach embargo -----------------------------------------------------
	_check("iron ore flows freely before the breach", \
		gate_svc.allow_drop("res_iron_ore"))
	_check("embargo_item accepts the breach call", \
		gate_svc.embargo_item("res_iron_ore", "dupe breach drill", "wg_admin"))
	_check("the ore is embargoed: allow_drop is the one seam that says no", \
		gate_svc.is_embargoed("res_iron_ore") and not gate_svc.allow_drop("res_iron_ore"))
	var row = DS.new().get_kv("ward_gate/embargo/res_iron_ore", null)
	_check("the embargo persists through the DictStore (reason, by, no expiry)", \
		row is Dictionary and str(row.get("reason", "")) == "dupe breach drill" \
		and str(row.get("by", "")) == "wg_admin" and absf(float(row.get("expires_at", -1.0))) < 0.001)
	_check("the live embargo list carries the ore", \
		Array(gate_svc.embargoed_items()).has("res_iron_ore"))
	var eg = WGD.new()
	eg.id = "gate_probe_embargo"
	var standing: Array[String] = ["res_iron_ore"]
	eg.embargoed_items = standing
	_check("the registry branch, proven on its own (in-memory gate)", \
		gate_svc.is_embargoed_for_gate(eg, "res_iron_ore") \
		and not gate_svc.is_embargoed_for_gate(eg, "potion_small"))
	_check("lift_embargo reopens the flow (breach handled)", \
		gate_svc.lift_embargo("res_iron_ore", "wg_admin") \
		and not gate_svc.is_embargoed("res_iron_ore"))
	_check("lifting twice is a no-op (none existed)", \
		not gate_svc.lift_embargo("res_iron_ore", "wg_admin"))
	DS.new().set_kv("ward_gate/embargo/res_iron_ore", \
		{"item_id": "res_iron_ore", "reason": "stale", "by": "wg_admin", \
		"placed_at": 0.0, "expires_at": float(Time.get_unix_time_from_system()) - 10.0})
	_check("an expired embargo erases itself on read (temporary is a contract)", \
		not gate_svc.is_embargoed("res_iron_ore") \
		and DS.new().get_kv("ward_gate/embargo/res_iron_ore", null) == null)

	# ---- D. The loot seam ------------------------------------------------------------
	_check("embargo for the drop test", gate_svc.embargo_item("res_iron_ore", "drop drill", "wg_admin"))
	var l1 = loot.create_container_loot("wg_chest", \
		[{"item_id": "res_iron_ore", "quantity": 5}, {"item_id": "potion_small", "quantity": 1}])
	var info1 = loot.get_loot_info(l1)
	var ids1: Array = []
	for it in info1.get("items", []):
		ids1.append(str(it.get("item_id", "")))
	_check("the duped ore never materializes: the drop spawns without it", \
		not ids1.has("res_iron_ore") and ids1.has("potion_small"))
	var l2 = loot.create_container_loot("wg_chest2", [{"item_id": "res_iron_ore", "quantity": 9}])
	var info2 = loot.get_loot_info(l2)
	_check("a fully-embargoed drop spawns NOTHING", \
		info2.get("items", []).is_empty())
	_check("lift for the clean-drop test", gate_svc.lift_embargo("res_iron_ore", "wg_admin"))
	var l3 = loot.create_container_loot("wg_chest3", \
		[{"item_id": "res_iron_ore", "quantity": 5}, {"item_id": "potion_small", "quantity": 1}])
	var ids3: Array = []
	for it in loot.get_loot_info(l3).get("items", []):
		ids3.append(str(it.get("item_id", "")))
	_check("after the lift, the ore flows again (temporary means temporary)", \
		ids3.has("res_iron_ore") and ids3.has("potion_small"))

	print("probe_ward_gate: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
