# test_item_use.gd - THE USE-DOOR RECEIPT: InventoryService.use_item()
# gates, consumes, and lands every buff_effects book the catalog
# authors. The whole project's consumables were books nobody read --
# this receipt holds the consumer to its own laws:
#
#   A. RAIL refusals (no bag / empty slot / not consumable / dead /
#      level gate / cooldown) EVERY ONE BY NAME, each without
#      consuming anything.
#   B. VALIDATE-THEN-PAY: a bad book refuses BEFORE a charge leaves
#      the slot; a good book consumes exactly ONE charge then lands.
#   C. THE INSTANT TRIO: heal / mana through the real body.
#   D. THE CLOCK LAWS: a stat buff is a real StatusEffect (mods ride
#      in, the entity's own duration timer expires it), a HoT heals
#      across its ticks and self-expires on its tick budget.
#   E. THE COOLDOWN BOOK: per-ITEM expiry keyed [player][item]; the
#      door re-opens exactly item.cooldown later (an injected book
#      write is the time-travel leg, the transport seam).
#   F. DATA TRUTH: every authored consumable's book validates clean
#      through the door's own validator; the drinkables carry their
#      authored values.
#
# Receipt-lore: the receipt uses the REAL Entity (Node3D) added to the
# tree (the timed effects need the body's own Timers running) and the
# documented register/pull pattern for bags. The body override on the
# DEFAULT chain is the door's injection seam (injectable resolvers,
# never product fakes); runtime rides the default chain, which the
# "no body" rail still exercises for a stranger in a headless boot.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

const Item = preload("res://core/schemas/item.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")
const EntityScript = preload("res://core/entities/entity.gd")

var _inv_svc = null
var _ds = null

func _init() -> void:
	call_deferred("_run")

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)

func _finish() -> void:
	print("--- ITEM USE: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)

func _count(id: String, inv) -> int:
	var n := 0
	for i in range(inv.get_total_slots()):
		var it = inv.get_item(i)
		if it != null and it.id == id:
			n += maxi(1, int(it.current_stack))
	return n

func _slot_of(inv, id: String) -> int:
	for i in range(inv.get_total_slots()):
		var it = inv.get_item(i)
		if it != null and it.id == id:
			return i
	return -1

func _run() -> void:
	var root_node := root
	_inv_svc = root_node.get_node_or_null("InventoryService")
	_ds = root_node.get_node_or_null("DataService")
	_check("InventoryService autoload present", _inv_svc != null)
	_check("use_item + validator exist", _inv_svc != null \
		and _inv_svc.has_method("use_item") and _inv_svc.has_method("validate_effects"))
	if _inv_svc == null:
		quit(1)
		return
	if _ds == null:
		_check("DataService autoload present", false)
		_finish()
		return

	var stranger := "test_use_stranger"

	# --- A. THE RAILS
	var r = _inv_svc.use_item("nobody_at_all", 0)
	_check("no inventory refuses", r.ok == false and r.reason == "no inventory")

	var inv: InventoryComponent = InventoryComponent.new()
	inv.set_owner_id(stranger)
	_inv_svc.register_inventory(stranger, inv)

	r = _inv_svc.use_item(stranger, 0)
	_check("empty slot refuses", r.ok == false and r.reason == "empty slot")

	var sword: Item = _ds.get_item("wep_iron_sword")
	inv.add_item(sword, 1)
	r = _inv_svc.use_item(stranger, _slot_of(inv, "wep_iron_sword"))
	_check("a weapon is not a drink", r.ok == false and r.reason == "not consumable")
	_check("the refusal left the blade in the bag", _count("wep_iron_sword", inv) == 1)

	# The default body chain finds nobody for a stranger in a headless
	# boot (EntityService never registers the id; the local player is
	# unset), so a DRINKABLE reaches the body gate and names it.
	var probe_drink: Item = Item.new()
	probe_drink.id = "probe_drink"
	probe_drink.display_name = "Probe Drink"
	probe_drink.description = "The body-rail probe."
	probe_drink.icon_path = "res://icons/items/potion_red_small.png"
	probe_drink.item_category = Item.ItemCategory.CONSUMABLE
	probe_drink.buff_effects = [{"type": "instant_heal", "value": 10}]
	inv.add_item(probe_drink, 1)
	r = _inv_svc.use_item(stranger, _slot_of(inv, "probe_drink"))
	_check("no body refuses", r.ok == false and r.reason == "no body")
	_check("the probe drink paid nothing", _count("probe_drink", inv) == 1)

	# --- THE REAL BODY (an Entity in-tree: the clock legs need its
	# timers running) wired through the door's own injection seam.
	var body: Entity = EntityScript.new()
	body.entity_id = stranger
	body.display_name = "UseSubject"
	root.add_child(body)
	_inv_svc._use_body_override = func(_pid: String):
		return body

	await process_frame
	await process_frame

	# --- C. THE DATA: the drinkables resolve through truth
	var potion_small: Item = _ds.get_item("potion_health_small")
	_check("potion_health_small resolves", potion_small != null)

	if potion_small == null:
		_finish()
		return

	_check("small potion book (instant_heal 50, cd 2)",
		potion_small.buff_effects.size() == 1 \
		&& str(potion_small.buff_effects[0].get("type")) == "instant_heal" \
		&& int(potion_small.buff_effects[0].get("value")) == 50 \
		&& float(potion_small.cooldown) == 2.0)

	var tea: Item = _ds.get_item("tea_mooncap_steep")
	var elixir: Item = _ds.get_item("elixir_ironblood")
	var mana_small: Item = _ds.get_item("potion_mana_small")
	_check("new use-lane drinkables resolve", tea != null && elixir != null && mana_small != null)

	inv.remove_item_by_id("wep_iron_sword", 1)

	# --- A cont.: the level rail rides a real gate (required_level
	# above the body's level refuses by name, consumes nothing).
	var lv_law: Item = Item.new()
	lv_law.id = "lv_law_potion"
	lv_law.display_name = "Ward Seal Draught"
	lv_law.description = "The seal refuses the unranked."
	lv_law.icon_path = "res://icons/items/potion_red_small.png"
	lv_law.item_category = Item.ItemCategory.CONSUMABLE
	lv_law.required_level = 999
	lv_law.cooldown = 1.0
	lv_law.buff_effects = [{"type": "instant_heal", "value": 10}]
	inv.add_item(lv_law, 2)
	r = _inv_svc.use_item(stranger, _slot_of(inv, "lv_law_potion"))
	_check("the level rail refuses by name", r.ok == false \
		&& r.reason == "not your level yet")
	_check("the level rail consumed nothing", _count("lv_law_potion", inv) == 2)

	# --- B. THE VALIDATE-THEN-PAY LAW (bad book = full refusal)
	var crooked: Item = Item.new()
	crooked.id = "crooked_draught"
	crooked.display_name = "Crooked Draught"
	crooked.description = "Authored by nobody, drunk by nobody."
	crooked.icon_path = "res://icons/items/potion_red_small.png"
	crooked.item_category = Item.ItemCategory.CONSUMABLE
	crooked.cooldown = 1.0
	crooked.buff_effects = [{"type": "vibes", "value": 10}]
	inv.add_item(crooked, 2)
	var bag_slot := _slot_of(inv, "crooked_draught")
	r = _inv_svc.use_item(stranger, bag_slot)
	_check("an unknown buff type refuses whole", r.ok == false \
		&& str(r.reason).begins_with("bad buff book"))
	_check("the crooked stack never moved", _count("crooked_draught", inv) == 2)

	# --- C+E: THE DRINK, the cooldown, the book's re-opening
	inv.remove_item_by_id("lv_law_potion", 2)
	inv.remove_item_by_id("crooked_draught", 2)
	inv.add_item(potion_small, 3)
	body.current_health = 40
	var small_before := _count("potion_health_small", inv)
	r = _inv_svc.use_item(stranger, _slot_of(inv, "potion_health_small"))
	_check("the small potion drinks", r.ok == true \
		&& str(r.item_id) == "potion_health_small")
	_check("exactly one charge left the stack", _count("potion_health_small", inv) == small_before - 1)
	_check("the heal landed (40 -> 90)", int(body.current_health) == 90)
	_check("the applied book is honest", r.applied.size() == 1 \
		&& str(r.applied[0].get("type")) == "instant_heal" \
		&& float(r.applied[0].get("value")) == 50.0 \
		&& bool(r.applied[0].get("landed")))

	r = _inv_svc.use_item(stranger, _slot_of(inv, "potion_health_small"))
	_check("cooldown refuses the second chug", r.ok == false \
		&& r.reason == "cooldown")
	_check("the cooldown refusal consumed nothing", _count("potion_health_small", inv) == small_before - 1)
	_check("the book names the leftover (~2 s)", float(r.remaining) > 0.0 \
		&& float(r.remaining) <= 2.0)

	# Time travel for the expiry leg: winding the door's own book key
	# backwards is the scripted equivalent of waiting the window out.
	_inv_svc._use_cooldowns[stranger]["potion_health_small"] = \
		Time.get_unix_time_from_system() - 1.0
	body.current_health = 35
	r = _inv_svc.use_item(stranger, _slot_of(inv, "potion_health_small"))
	_check("an expired book re-opens the door", r.ok == true)
	_check("the heal followed the book (35 -> 85)", int(body.current_health) == 85)

	# --- F. THE DATA LAW: every authored consumable validates clean
	var vbad: Array = []
	var dir := DirAccess.open("res://data/consumables")
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tres"):
			var c = load("res://data/consumables/" + fn)
			if c == null:
				vbad.append("load failed: " + fn)
			elif not c.buff_effects.is_empty():
				var bad: Array = _inv_svc.validate_effects(c)
				if not bad.is_empty():
					vbad.append("%s: %s" % [c.id, ", ".join(bad)])
		fn = dir.get_next()
	_check("every authored book validates clean", vbad.is_empty())
	if not vbad.is_empty():
		print("    defects: " + str(vbad.slice(0, 4)))

	# --- F cont.: the new drinkables' authored values
	_check("the tea's book (25 x 8 s every 2 s)", tea != null \
		&& str(tea.buff_effects[0].get("type")) == "heal_over_time" \
		&& int(tea.buff_effects[0].get("value")) == 25 \
		&& float(tea.buff_effects[0].get("duration")) == 8.0 \
		&& float(tea.buff_effects[0].get("interval")) == 2.0)
	_check("the elixir's book (strength +8 / 45 s)", elixir != null \
		&& str(elixir.buff_effects[0].get("stat")) == "strength" \
		&& int(elixir.buff_effects[0].get("value")) == 8 \
		&& float(elixir.buff_effects[0].get("duration")) == 45.0)
	_check("the mana potion's book (instant 40)", mana_small != null \
		&& str(mana_small.buff_effects[0].get("type")) == "instant_mana" \
		&& int(mana_small.buff_effects[0].get("value")) == 40)

	# --- D: THE CLOCK LAWS with fast dials (receipt stub items for
	# the TIMING math; the authored values ride above untouched).
	if elixir != null:
		body.level = 10  # the elixir's own required_level = 4 gate is honest data
		_inv_svc._use_cooldowns[stranger]["elixir_ironblood"] = 0.0
		inv.add_item(elixir, 1)
		var strength_before: int = int(body.get_stat("strength"))
		r = _inv_svc.use_item(stranger, _slot_of(inv, "elixir_ironblood"))
		var buff_fx = null
		for fx in body.status_effects:
			if str(fx.effect_id) == "elixir_ironblood_stat_buff":
				buff_fx = fx
		_check("the elixir drinks + lands its buff", r.ok == true && buff_fx != null)
		_check("the mod rides the body (+8 strength)", \
			int(body.get_stat("strength")) == strength_before + 8)
		# Fast expiry: the effect's own timer carries the duration; we
		# do NOT shrink the ITEM data -- the law intent is the body's
		# real timer runs it, so the leg just winds the FX timer down.
		if buff_fx != null:
			if buff_fx._timer != null:
				buff_fx._timer.start(0.25)
			var waited := 0.0
			while waited < 3.0 \
				and not body.status_effects.is_empty() \
				and body.status_effects.has(buff_fx):
				await process_frame
				waited += 1.0 / 60.0
			_check("the buff expires through the body's own timer",
				not body.status_effects.has(buff_fx))
			_check("the mod unwound on expiry", int(body.get_stat("strength")) == strength_before)

	# THE HoT with its fast dial: real ticks, real heal, real expiry.
	var hot: Item = Item.new()
	hot.id = "hot_test_brew"
	hot.display_name = "Receipt Broth"
	hot.description = "A fast dial for the tick law."
	hot.icon_path = "res://icons/items/tea_mooncap.png"
	hot.item_category = Item.ItemCategory.CONSUMABLE
	hot.cooldown = 0.0
	hot.buff_effects = [{"type": "heal_over_time", "value": 10, "interval": 0.2, "duration": 1.0}]
	inv.add_item(hot, 1)
	body.current_health = 20
	var hp0 := int(body.current_health)
	r = _inv_svc.use_item(stranger, _slot_of(inv, "hot_test_brew"))
	_check("the broth drinks", r.ok == true)
	var healed_up := false
	var expired_out := false
	var waited2 := 0.0
	while true:
		await process_frame
		waited2 += 1.0 / 60.0
		if body.current_health > hp0:
			healed_up = true
		# The HoT's tick budget is interval x ticks; its own timer path
		# expires it. Was status cleared?
		expired_out = true
		for fx in body.status_effects:
			if str(fx.effect_id) == "hot_test_brew_heal_over_time":
				expired_out = false
		if (healed_up && expired_out) or waited2 > 4.0:
			break
	_check("the HoT healed across ticks", healed_up)
	_check("the HoT expired on its tick budget", expired_out)

	# THE INSTANT MANA leg through the real body.
	_inv_svc._use_cooldowns[stranger]["potion_mana_small"] = 0.0
	inv.add_item(mana_small, 1)
	body.current_mana = 10
	r = _inv_svc.use_item(stranger, _slot_of(inv, "potion_mana_small"))
	_check("the mana drink lands (10 -> 50)", r.ok == true \
		&& int(body.current_mana) == 50)

	_finish()
