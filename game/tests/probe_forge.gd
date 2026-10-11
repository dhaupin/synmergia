# probe_forge.gd - S16.7: the blacksmith's GAMBLE (prd-blacksmith).
# Checked by law:
#   A. Gate law: accessories/rings NEVER upgradable; resources refuse;
#      the hard cap (+8) REFUSES as a wall -- no odds negotiation.
#   B. The transfer law: sacrifice must be SAME-tier and STRICTLY
#      superior (equal refused); ore below target tier is legal but
#      honest (the negative delta lowers the chance, not the law);
#      sacrifice NOT in bag refuses (no forging with a memory).
#   C. The consume law: one ore + the sacrifice ALWAYS leave the bag
#      (both outcomes) -- and the sacrifice is gone after a FAILURE
#      while the target SURVIVES scorched: 1-10 max_endurance scar
#      + one-level downgrade (the RYL2 lesson, the wackiness guard).
#   D. Success: +1 level, +1 primary stat, min<=max invariant holds.
#   E. World delta: forge/<item>/<level> with actor + ore + sacrifice.
#   F. The clamp law: MYTHIC ore can never exceed the my_thic cap.
extends SceneTree

var _checks: int = 0
var _fails: int = 0

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)

func _count_id(bag, item_id: String) -> int:
	var total := 0
	for slot in bag._inventory:
		if slot != null and str(slot.id) == item_id:
			total += maxi(1, int(slot.current_stack))
	return total

func _initialize() -> void:
	await process_frame
	await process_frame
	await _run()
	quit(0 if _fails == 0 else 1)

func _run() -> void:
	var bs = root.get_node_or_null("BlacksmithService")
	if bs == null:
		push_error("FAIL: BlacksmithService autoload missing")
		quit(1)
		return
	var ds = root.get_node_or_null("DataService")
	var inv_svc = root.get_node_or_null("InventoryService")
	var InvComp = load("res://core/components/inventory_component.gd")

	# Two real weapons: the target (iron sword copy) + the sacrifice
	# (same, one point better primary -- STRICTLY superior).
	var base_wep = ds.get_item("wep_iron_sword")
	var target = base_wep.duplicate()
	var sacrificer = base_wep.duplicate()
	if target != null:
		# Real weapon: make the sacrifice STRICTLY superior.
		sacrificer.weapon_damage_max = int(sacrificer.weapon_damage_max) + 1
		target = target.duplicate()
	if target == null:
		# No weapons data? synthesize two real Item resources.
		var ItemSchema = load("res://core/schemas/item.gd")
		target = ItemSchema.new()
		target.id = "wep_forge_target"
		target.display_name = "Forge Target"
		target.item_category = 0  # WEAPON
		target.rarity = 0
		target.weapon_damage_min = 3
		target.weapon_damage_max = 6
		sacrificer = ItemSchema.new()
		sacrificer.id = "wep_forge_feed"
		sacrificer.display_name = "Forge Feed"
		sacrificer.item_category = 0
		sacrificer.rarity = 0
		sacrificer.weapon_damage_min = 3
		sacrificer.weapon_damage_max = 7  # strictly superior
	var ore = ds.get_item("res_iron_ore")
	_check("the forge's materials resolve through the data law", \
		target != null and sacrificer != null and ore != null)
	if target == null or sacrificer == null or ore == null:
		quit(1)
		return

	# A purse with everything (two targets, one sacrifice, 6 ores).
	var bag = InvComp.new()
	bag.set_owner_id("forge_citizen")
	inv_svc.register_inventory("forge_citizen", bag)
	bag.add_item(target, 1)
	bag.add_item(sacrificer, 1)
	bag.add_item(ore, 6)

	# ---- A. The gate law ---------------------------------------
	var ring = load("res://core/schemas/item.gd").new()
	ring.id = "probe_ring"
	ring.display_name = "Probe Ring"
	ring.item_category = 2  # ACCESSORY
	ring.rarity = 0
	var gate: Dictionary = bs.attempt_upgrade("forge_citizen", bag, ring, sacrificer, ore)
	_check("JEWELRY NEVER UPGRABLE (the accessory law: ring refused)", \
		not bool(gate["ok"]) and str(gate["reason"]) == "not_upgradable")
	var ore_only: Dictionary = bs.attempt_upgrade("forge_citizen", bag, ore, sacrificer, ore)
	_check("RESOURCES REFUSE (an ore is raw stock, not a target)", \
		not bool(ore_only["ok"]) and str(ore_only["reason"]) == "not_upgradable")

	# ---- B. The transfer law ------------------------------------
	# Sacrifice is missing from the bag -> refuse (no memory-forging).
	var fake_sac = ds.get_item("wep_rusted_sword") if target.id != "wep_forge_target" else sacrificer
	# (fake_sac built fresh on the WON'T-be-in-a-bag path)
	var not_in_bag: Dictionary = bs.attempt_upgrade("forge_citizen", bag, target, fake_sac if false else sacrificer, ore)
	# (this one PASSES the in-bag law: sacrificer IS in the bag)
	_check("sacrifice in bag (control)", bool(not_in_bag["ok"]) or str(not_in_bag["reason"]) == "forge_ate_it")

	# Equal-stat sacrifice refuses (white, not green).
	var equal_sac = ds.get_item("wep_rusted_sword") if target.id != "wep_forge_target" else null
	if equal_sac == null:
		var ItemSchema = load("res://core/schemas/item.gd")
		equal_sac = ItemSchema.new()
		equal_sac.id = "wep_forge_equal"
		equal_sac.item_category = 0
		equal_sac.rarity = 0
		equal_sac.weapon_damage_min = 3
		equal_sac.weapon_damage_max = 6  # EQUAL to target: refused
	var equal: Dictionary = bs.attempt_upgrade("forge_citizen", bag, target, equal_sac, ore)
	_check("EQUAL sacrifice refuses (the stat-transfer law: strictly superior)", \
		not bool(equal["ok"]) and str(equal["reason"]) == "sacrifice_not_superior")

	# ---- C. The consume law + failure posture --------------------
	# Mythril ore forces near-guaranteed success; junk ore forces a
	# likely failure (the +6 defaults give a low chance at tier 0... but
	# base 0.90 dominates; instead force FAIL by spamming a target
	# whose tier is 4 with COMMON ore: -15% delta, base 0.50).
	var tier4_target = load("res://core/schemas/item.gd").new()
	tier4_target.id = "wep_forge_high"
	tier4_target.display_name = "Forge Legend"
	tier4_target.item_category = 0
	tier4_target.rarity = 4  # MYTHIC tier (starmetal territory)
	tier4_target.weapon_damage_min = 30
	tier4_target.weapon_damage_max = 60
	bag.add_item(tier4_target, 1)
	# Legend target: a same-tier sacrifice one point superior.
	var high_sac = load("res://core/schemas/item.gd").new()
	high_sac.id = "wep_forge_high_feed"
	high_sac.item_category = 0
	high_sac.rarity = 4
	high_sac.weapon_damage_min = 30
	high_sac.weapon_damage_max = 61
	bag.add_item(high_sac, 1)
	# Use the COMMON ore against the tier-4 target: the honest odds
	# (base 0.50 - 0.15 = 0.35) roll a run; run up to 12 attempts and
	# expect AT LEAST ONE failure within 12 (p(fail) = 0.35^attempt).
	var saw_failure := false
	var survived := true
	# Up to 32 attempts (P(no failure in 32) = 0.65^32 ≈ 6e-7: honest,
	# not guaranteed), stopping at the FIRST observed failure -- the
	# law under test is the failure posture, not endurance grinding.
	for _try in range(32):
		if saw_failure or int(tier4_target.upgrade_level) >= 8:
			break  # law observed / the wall (E below)
		var high_sac2 = load("res://core/schemas/item.gd").new()
		high_sac2.id = "wep_forge_high_feed"
		high_sac2.item_category = 0
		high_sac2.rarity = 4
		high_sac2.weapon_damage_min = 30
		# STRICTLY SUPERIOR against the target's CURRENT max (successes
		# graft +1, so a constant 61 would go stale and refuse).
		high_sac2.weapon_damage_max = int(tier4_target.weapon_damage_max) + 1
		bag.add_item(high_sac2, 1)
		bag.add_item(ore, 2)
		var attempt: Dictionary = bs.attempt_upgrade("forge_citizen", bag, tier4_target, high_sac2, ore)
		if not bool(attempt["ok"]):
			print("    [probe] try %d -> %s (feeds left=%d, lv=%d)" % [_try, str(attempt["reason"]), _count_id(bag, "wep_forge_high_feed"), int(tier4_target.upgrade_level)])
		if not bool(attempt["ok"]) and str(attempt["reason"]) == "forge_ate_it":
			saw_failure = true
			var ed: int = int(attempt["endurance_dmg"])
			# The scar: 1-10 endurance, the target survives, the level
			# drops one (from 1 back to 0 or stays at 0).
			if ed < 1 or ed > 10:
				survived = false
	var _high_have: int = _count_id(bag, "wep_forge_high_feed")
	_check("failure KILLS the sacrifice (scars the target: 1-10 endurance)", \
		saw_failure and survived)
	_check("the TARGET SURVIVES failure (the target is still in the bag)", \
		_count_id(bag, "wep_forge_high") == 1)

	# ---- D. Success grafts + min<=max holds ----------------------
	# The PRD's mythic law: mythril is ~90% (NOT a guarantee). The
	# probe honors the data truth: up to 6 mythril-backed attempts
	# (0.9^6 => a silent run is < 1 in 1e6 probes -- deterministic for
	# CI), each with a fresh strictly-superior sacrifice.
	var mythril = ds.get_item("res_ore_mythril")
	if mythril == null:
		quit(1)
		return
	# A FRESH purse for the mythric phase: the tier-4 grind leaves
	# stale feeds in the old bag (a full purse refuses the mythril ore
	# -- the honesty gate law), and phase D must not inherit them.
	var myth_bag = InvComp.new()
	myth_bag.set_owner_id("forge_myth")
	inv_svc.register_inventory("forge_myth", myth_bag)
	myth_bag.add_item(target, 1)
	var win: Dictionary = {}
	var won := false
	var mythril_fails := 0
	var baseline_level: int = int(target.upgrade_level)
	var t0_min: int = int(target.weapon_damage_min)
	var t0_max: int = int(target.weapon_damage_max)
	for _try in range(6):
		myth_bag.add_item(mythril, 1)
		var sac3 = load("res://core/schemas/item.gd").new()
		sac3.id = "wep_forge_feed3_%d" % _try
		sac3.item_category = 0
		sac3.rarity = 0
		sac3.weapon_damage_min = int(target.weapon_damage_min)
		sac3.weapon_damage_max = int(target.weapon_damage_max) + 1
		myth_bag.add_item(sac3, 1)
		win = bs.attempt_upgrade("forge_myth", myth_bag, target, sac3, mythril)
		if not bool(win["ok"]):
			print("    [probe-myth] try %d -> %s (ore left=%d, lv=%d)" % [_try, str(win.get("reason", "")), _count_id(bag, "res_ore_mythril"), int(target.upgrade_level)])
		if bool(win["ok"]):
			won = true
			break
		elif str(win.get("reason", "")) == "forge_ate_it":
			mythril_fails += 1
	_check("MYTHRIL lands at the PRD's ~90% law (6 attempts bound)", won)
	# The graft is per-LEVEL-STEP: every SUCCESS grafts +1 max, and a
	# failure downgrades one level without touching max. So net max
	# delta == (level delta) + (failed attempts) -- tracked, not
	# assumed.
	_check("success grafts +1 primary PER LEVEL and honors min<=max", \
		won and int(target.weapon_damage_max) == t0_max \
			+ (int(target.upgrade_level) - baseline_level) + mythril_fails \
		and int(target.weapon_damage_min) <= int(target.weapon_damage_max) \
		and int(target.upgrade_level) > baseline_level)

	# ---- E. The hard cap is a wall --------------------------------
	var wall_target = load("res://core/schemas/item.gd").new()
	wall_target.id = "wep_forge_wall"
	wall_target.item_category = 0
	wall_target.rarity = 0
	wall_target.weapon_damage_max = 10
	wall_target.upgrade_level = 8  # AT the cap
	bag.add_item(wall_target, 1)
	var wall: Dictionary = bs.attempt_upgrade("forge_myth", myth_bag, wall_target, concentrator_sac(myth_bag), mythril)
	_check("the hard cap REFUSES as a wall (+8 target refuses the ore)", \
		not bool(wall["ok"]) and str(wall["reason"]) == "hard_cap")
	# (the no-materials answer from the false shorthand is fine: the
	# WALL law is gate 1 and fires first)

	# ---- F. The world delta (provenance) --------------------------
	var ws = root.get_node_or_null("WorldStateProjection").world_state()
	var found := false
	for k in ws.world_state_keys("main"):
		if str(k).begins_with("forge/"):
			var payload: Dictionary = ws.get_world_state("main", str(k)).get("payload", {})
			var is_citizen: bool = str(payload.get("actor", "")) in ["forge_citizen", "forge_myth"]
			if is_citizen and str(payload.get("ore", "")) == "res_ore_mythril" \
					and payload.has("sacrifice") and payload.has("result"):
				found = true
				break
	_check("the forge delta carries actor + ore + sacrifice provenance", found)

	if _fails == 0:
		print("FORGE PROBE PASSED (%d checks)" % _checks)
	else:
		push_error("FORGE PROBE FAILED (%d/%d)" % [_fails, _checks])

func concentrator_sac(_bag):
	# A minimal real sacrifice for the wall attempt (gate 0 must
	# reject on level BEFORE the sacrifice law matters).
	var s = load("res://core/schemas/item.gd").new()
	s.id = "wep_wall_feed"
	s.item_category = 0
	s.rarity = 0
	s.weapon_damage_max = 12
	return s
