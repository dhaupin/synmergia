## test_equipment_vocabulary.gd - the appended equipment vocabulary and the
## tablet world-ward lane.
##
##   A. APPEND-ONLY ENUMS: every pre-existing equip slot / accessory type /
##      item category / mount kind keeps its numeric value; the new ARMS,
##      TABLET, BREATHER, capacity lanes and GLIDER values are appended.
##   B. TABLETS ARE REAL EQUIPMENT: every tablet record is a TABLET in the
##      TABLET slot, carries a nonzero baseline ward, and all seven focuses
##      have a seed record. Higher rarity/level buys more mitigation.
##   C. THE LIVE CONSUMER: equip/unequip/broken tablet changes the ward; the
##      sea's "drowning" tag resolves through WorldHazard to the DEEP focus.
##   D. HEAD HELM + BREATHER LAYER: the diving helm is HEAD armor (armor is
##      live, air is not); the reed/pearl breathers use their own slot.
##   E. ARMS + GLIDER: the appended armor slot and glider kind load from data.
##
## Run headless:
##   godot --headless --path game --script res://tests/test_equipment_vocabulary.gd
## Exit 0 = all pass.
extends SceneTree

const ItemScript = preload("res://core/schemas/item.gd")
const InventoryScript = preload("res://core/components/inventory_component.gd")
const WorldHazard = preload("res://core/schemas/world_hazard.gd")
const MountDataScript = preload("res://core/schemas/mount_data.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	print("--- EQUIPMENT VOCABULARY: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func _run() -> void:
	# --- A. Append-only identity -----------------------------------------
	_check(int(ItemScript.EquipSlot.HEAD) == 1, "HEAD keeps its pre-existing value")
	_check(int(ItemScript.EquipSlot.SHOULDERS) == 6, "SHOULDERS keeps its pre-existing value")
	_check(int(ItemScript.EquipSlot.BELT) == 13, "BELT keeps its pre-existing value")
	_check(int(ItemScript.EquipSlot.ARMS) == 14, "ARMS is appended after BELT")
	_check(int(ItemScript.EquipSlot.TABLET) == 15, "TABLET keeps its appended value")
	_check(int(ItemScript.EquipSlot.BREATHER) == 16, "BREATHER is appended after TABLET")
	_check(int(ItemScript.EquipSlot.RING_10) == 24, "RING_10 is the appended ring ceiling")
	_check(int(ItemScript.EquipSlot.NECKLACE_3) == 26, "NECKLACE_3 is the appended amulet ceiling")
	_check(int(ItemScript.EquipSlot.CLOAK_3) == 30, "CLOAK_3 is the appended cloak ceiling")
	_check(int(ItemScript.AccessoryType.BREATHER) == 6, "BREATHER keeps its pre-existing value")
	_check(int(ItemScript.AccessoryType.UNDERWATER_HELM) == 7, "UNDERWATER_HELM is appended")
	_check(int(ItemScript.AccessoryType.TABLET) == 8, "TABLET accessory type is appended")
	_check(int(ItemScript.ItemCategory.SKILL_BOOK) == 9, "SKILL_BOOK keeps its pre-existing value")
	_check(int(ItemScript.ItemCategory.TABLET) == 10, "TABLET item category is appended")
	_check(int(MountDataScript.MountKind.SPACE) == 3, "SPACE keeps its pre-existing mount value")
	_check(int(MountDataScript.MountKind.GLIDER) == 4, "GLIDER mount kind is appended")

	# --- B. Tablet records ------------------------------------------------
	var tablet_dir := DirAccess.open("res://data/accessories")
	var tablets: Dictionary = {}
	if tablet_dir == null:
		_check(false, "data/accessories exists")
	else:
		tablet_dir.list_dir_begin()
		var fn := tablet_dir.get_next()
		while fn != "":
			if fn.ends_with(".tres"):
				var item = load("res://data/accessories/" + fn)
				if item != null and int(item.item_category) == int(ItemScript.ItemCategory.TABLET):
					tablets[str(item.id)] = item
			fn = tablet_dir.get_next()
	_check(tablets.size() >= 7, "tablet seed catalog reaches every focus (%d records)" % tablets.size())
	var focus_seen: Dictionary = {}
	var bad_tablets: Array = []
	for id in tablets:
		var t = tablets[id]
		focus_seen[int(t.tablet_domain)] = true
		if not t.is_tablet():
			bad_tablets.append(id + " not in the TABLET slot/type")
		if t.tablet_world_ward <= 0.0:
			bad_tablets.append(id + " has no baseline ward")
		if t.get_world_ward("deep") <= 0.0 or t.get_world_ward("deep") > 0.9:
			bad_tablets.append(id + " deep ward outside 0..0.9")
		if t.durability_loss_rate > 0.5:
			bad_tablets.append(id + " decays like a weapon, not a tablet")
	_check(bad_tablets.is_empty(), "every tablet is baseline-functional: " + "; ".join(bad_tablets.slice(0, 4)))
	for domain in range(int(ItemScript.TabletDomain.WORLD), int(ItemScript.TabletDomain.VOID) + 1):
		_check(focus_seen.has(domain), "tablet focus %d has a seed record" % domain)

	var clay = tablets.get("acc_tablet_clay")
	var tide = tablets.get("acc_tablet_tide")
	var void_tablet = tablets.get("acc_tablet_void")
	_check(clay != null and tide != null and void_tablet != null, "clay/tide/void tablets load")
	if clay != null and tide != null and void_tablet != null:
		_check(tide.get_world_ward("deep") > tide.tablet_world_ward,
			"a DEEP tablet adds its focus ward to the baseline")
		_check(_near(tide.get_world_ward("heat"), tide.tablet_world_ward),
			"a DEEP tablet leaves heat at the baseline ward")
		_check(void_tablet.get_world_ward("void") > tide.get_world_ward("deep"),
			"higher rarity/level buys more mitigation")
		_check(void_tablet.rarity > clay.rarity and void_tablet.item_level > clay.item_level,
			"the void tablet is the higher-level/rarity rung")

	# --- C. Equip / break / save / hazard consumer ------------------------
	var bag = InventoryScript.new()
	bag.name = "InventoryComponent"
	root.add_child(bag)
	var tide_copy = tide.duplicate() if tide != null else null
	if tide_copy != null:
		bag.add_item(tide_copy)
		var idx := bag.find_item("acc_tablet_tide")
		_check(idx >= 0 and bag.equip_item(idx), "a tablet equips through the shared inventory")
		var equipped = bag.get_equipped(ItemScript.EquipSlot.TABLET)
		_check(equipped != null and equipped.is_tablet(), "the TABLET socket holds the tablet")
		var deep_ward := bag.get_world_ward("deep")
		_check(deep_ward > 0.0, "the equipped tablet answers a deep-hazard query")
		_check(bag.get_world_ward("physical") == 0.0, "a tablet does not leak into combat school resists")
		_check(WorldHazard.is_hazard("drowning") and WorldHazard.normalize("drowning") == "deep",
			"the sea's drowning tag resolves to the DEEP hazard")
		_check(not WorldHazard.is_hazard("fire"), "a combat school is not a world hazard")
		var expected := maxi(1, int(ceil(100.0 * (1.0 - deep_ward))))
		_check(WorldHazard.mitigate(bag, 100, "drowning") == expected,
			"the world-hazard helper applies the equipped tablet's ward")
		_check(WorldHazard.mitigate(bag, 100, "heat") == maxi(1, int(ceil(100.0 * (1.0 - bag.get_world_ward("heat"))))),
			"an off-focus hazard still gets the baseline ward")

		var saved: Dictionary = equipped.to_dict()
		var restored = ItemScript.from_dict(saved)
		_check(restored.is_tablet(), "tablet identity survives a save round-trip")
		_check(_near(restored.tablet_world_ward, equipped.tablet_world_ward),
			"tablet baseline ward survives a save round-trip")
		_check(_near(restored.tablet_domain_ward, equipped.tablet_domain_ward),
			"tablet focus ward survives a save round-trip")

		equipped.current_durability = 0
		_check(bag.get_world_ward("deep") == 0.0, "a broken tablet stops guarding")
		equipped.current_durability = equipped.max_durability

	# Entity/enemy parity: the shared bag read is the body read.
	var EnemyScript = load("res://entities/enemy.gd")
	var body_entity = EnemyScript.new()
	body_entity.entity_id = "vocab_enemy"
	body_entity.inventory_component = bag
	root.add_child(body_entity)
	_check(body_entity.get_world_ward("deep") > 0.0,
		"the shared Entity surface reads the tablet ward (enemies included)")

	# --- D. HEAD helm + separate BREATHER layer --------------------------
	var helm = load("res://data/armors/arm_diving_helm.tres")
	_check(helm != null, "the underwater helm record loads")
	if helm != null:
		_check(int(helm.item_category) == int(ItemScript.ItemCategory.ARMOR),
			"the diving helm is armor, not an accessory")
		_check(int(helm.accessory_type) == int(ItemScript.AccessoryType.UNDERWATER_HELM),
			"the diving helm carries UNDERWATER_HELM")
		_check(int(helm.equip_slot) == int(ItemScript.EquipSlot.HEAD),
			"the diving helm occupies HEAD")
		_check(not helm.is_breather(), "the HEAD diving helm is not the air layer")
		var helm_bag = InventoryScript.new()
		helm_bag.name = "InventoryComponent"
		root.add_child(helm_bag)
		helm_bag.add_item(helm.duplicate())
		var hidx := helm_bag.find_item("arm_diving_helm")
		_check(hidx >= 0 and helm_bag.equip_item(hidx), "the diving helm equips at HEAD")
		_check(helm_bag.get_equipped_breather() == null,
			"a HEAD helm supplies no breather body")
		_check(helm_bag.get_equipment_armor() >= int(helm.armor_value),
			"the helm's armor line stays live underwater")

		var reed = load("res://data/accessories/acc_breather_reed.tres")
		_check(reed != null and int(reed.equip_slot) == int(ItemScript.EquipSlot.BREATHER),
			"the reed breather authors the separate BREATHER slot")
		helm_bag.add_item(reed.duplicate())
		var ridx := helm_bag.find_item("acc_breather_reed")
		_check(ridx >= 0 and helm_bag.equip_item(ridx), "the reed equips beside the helm")
		var equipped_breather = helm_bag.get_equipped_breather()
		_check(equipped_breather != null and str(equipped_breather.id) == "acc_breather_reed",
			"the inventory resolves the BREATHER layer")

		var inv_svc = root.get_node_or_null("InventoryService")
		var ocean = root.get_node_or_null("OceanService")
		_check(inv_svc != null and ocean != null, "OceanService + InventoryService autoloads are present")
		if inv_svc != null and ocean != null:
			inv_svc.register_inventory("vocab_probe", helm_bag)
			var profile: Dictionary = ocean.breather_for("vocab_probe")
			_check(_near(float(profile.get("mult", 0.0)), 2.0),
				"OceanService resolves the BREATHER layer's air multiplier")
			_check(_near(float(profile.get("grace_m", 0.0)), 2.0),
				"OceanService resolves the BREATHER layer's squeeze grace")
			# One air layer: a better breather replaces the reed, never stacks.
			helm_bag.add_item(load("res://data/accessories/acc_breather_abyss_pearl.tres"))
			var nidx := helm_bag.find_item("acc_breather_abyss_pearl")
			if nidx >= 0:
				helm_bag.equip_item(nidx)
			var best: Dictionary = ocean.breather_for("vocab_probe")
			_check(_near(float(best.get("mult", 0.0)), 8.0),
				"the better breather replaces the reed in the one air layer")
			_check(helm_bag.get_equipped(ItemScript.EquipSlot.NECKLACE) == null,
				"the amulet lane stays free for a necklace")
			inv_svc.unregister_inventory("vocab_probe")

	# --- E. ARMS armor + GLIDER mount kind --------------------------------
	var armguards = load("res://data/armors/arm_iron_armguards.tres")
	_check(armguards != null and int(armguards.equip_slot) == int(ItemScript.EquipSlot.ARMS),
		"the armguards seed sets the appended ARMS slot")
	_check(armguards != null and int(armguards.armor_value) > 0,
		"the ARMS armor carries a real armor value")
	var glider = load("res://data/gliders/glider_drift_kite.tres")
	_check(glider != null and int(glider.kind) == int(MountDataScript.MountKind.GLIDER),
		"glider records author the appended GLIDER kind")
	_check(glider != null and glider.is_glider() and not glider.bails_on_fall(),
		"a glider is its own kind and does not use the ground mount's cliff bail")
