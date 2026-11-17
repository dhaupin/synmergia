## test_equipment_capacity.gd - data-authored accessory capacity, the
## separate HEAD/BREATHER layers, and the guaranteed starter tablet.
##
##   A. DATA: equipment_capacity.tres authors 2 rings / 1 amulet / 1 belt /
##      1 cloak today, and the appended lanes can carry 10 / 3 / 3 / 3.
##   B. CAPACITY: two rings equip; a third lane is refused. A designer
##      override opens ten ring lanes and three amulet lanes without code.
##   C. SPLIT: a HEAD diving helm contributes armor but no air; a BREATHER
##      item resolves through OceanService from its own layer.
##   D. STARTER TABLET: guaranteed, soulbound, indestructible, equipped
##      directly even with a full bag, and present in every starter table.
##
## Run headless:
##   godot --headless --path game --script res://tests/test_equipment_capacity.gd
## Exit 0 = all pass.
extends SceneTree

const ItemScript = preload("res://core/schemas/item.gd")
const InventoryScript = preload("res://core/components/inventory_component.gd")
const CapacityScript = preload("res://core/schemas/equipment_capacity_data.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	_run()
	print("--- EQUIPMENT CAPACITY: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _ring(item_id: String) -> Resource:
	var item = ItemScript.new()
	item.id = item_id
	item.display_name = item_id
	item.item_category = ItemScript.ItemCategory.ACCESSORY
	item.accessory_type = ItemScript.AccessoryType.RING
	item.equip_slot = ItemScript.EquipSlot.RING_1
	item.stack_size = 1
	return item

func _necklace(item_id: String) -> Resource:
	var item = ItemScript.new()
	item.id = item_id
	item.display_name = item_id
	item.item_category = ItemScript.ItemCategory.ACCESSORY
	item.accessory_type = ItemScript.AccessoryType.NECKLACE
	item.equip_slot = ItemScript.EquipSlot.NECKLACE
	item.stack_size = 1
	return item

func _bag(slots: int = 32) -> InventoryComponent:
	var bag := InventoryScript.new()
	bag.max_inventory_slots = slots
	root.add_child(bag)
	return bag

func _run() -> void:
	# --- A. Data-authored table ------------------------------------------
	var data_record = load("res://data/balance/equipment_capacity.tres")
	_check(data_record != null and data_record.is_valid(),
		"the capacity balance record loads")
	if data_record != null:
		_check(int(data_record.ring_slots) == 2, "the live table authors two rings")
		_check(int(data_record.amulet_slots) == 1, "the live table authors one amulet")
		_check(int(data_record.belt_slots) == 1, "the live table authors one belt")
		_check(int(data_record.cloak_slots) == 1, "the live table authors one cloak")
	_check(CapacityScript.MAX_RING_SLOTS == 10, "the appended ring ceiling is ten")
	_check(CapacityScript.MAX_AMULET_SLOTS == 3, "the appended amulet ceiling is three")

	# --- B. Two rings today, ten by data ---------------------------------
	var bag := _bag()
	var two_ok := true
	for i in range(2):
		var ring := _ring("test_ring_%d" % i)
		two_ok = two_ok and bag.add_item(ring)
		two_ok = two_ok and bag.equip_item(bag.find_item(ring.id))
	_check(two_ok and bag.get_equipped(ItemScript.EquipSlot.RING_1) != null
		and bag.get_equipped(ItemScript.EquipSlot.RING_2) != null,
		"two rings fill RING_1 and RING_2")
	var third := _ring("test_ring_third")
	bag.add_item(third)
	var third_idx := bag.find_item(third.id)
	_check(not bag.can_equip_in_slot(third, ItemScript.EquipSlot.RING_3),
		"the third ring lane is refused at capacity 2")
	_check(not bag.equip_item(third_idx, ItemScript.EquipSlot.RING_3),
		"the third ring cannot be forced into RING_3")

	var wide := _bag()
	var wide_cap := CapacityScript.new()
	wide_cap.ring_slots = 10
	wide_cap.amulet_slots = 3
	wide.equipment_capacity_override = wide_cap
	var ten_ok := true
	for i in range(10):
		var ring := _ring("test_wide_ring_%d" % i)
		ten_ok = ten_ok and wide.add_item(ring)
		ten_ok = ten_ok and wide.equip_item(
			wide.find_item(ring.id), InventoryScript.RING_SLOT_ORDER[i])
	_check(ten_ok and wide.get_all_equipment().size() == 10,
		"a data override opens ten ring lanes without code")
	var three_ok := true
	for i in range(3):
		var necklace := _necklace("test_amulet_%d" % i)
		three_ok = three_ok and wide.add_item(necklace)
		three_ok = three_ok and wide.equip_item(wide.find_item(necklace.id))
	_check(three_ok and wide.get_equipped(ItemScript.EquipSlot.NECKLACE) != null
		and wide.get_equipped(ItemScript.EquipSlot.NECKLACE_2) != null
		and wide.get_equipped(ItemScript.EquipSlot.NECKLACE_3) != null,
		"a data override opens three amulet lanes")

	# --- C. Helm and breather are separate layers ------------------------
	var diver := _bag()
	var helm = load("res://data/armors/arm_diving_helm.tres")
	var reed = load("res://data/accessories/acc_breather_reed.tres")
	_check(helm != null and int(helm.equip_slot) == ItemScript.EquipSlot.HEAD,
		"the diving helm loads at HEAD")
	_check(helm != null and not helm.is_breather(),
		"the HEAD helm is not the air layer")
	_check(reed != null and int(reed.equip_slot) == ItemScript.EquipSlot.BREATHER,
		"the reed breather loads at BREATHER")
	_check(reed != null and reed.is_breather(), "the BREATHER item is a breather")
	var helm_ok: bool = diver.equip_direct(helm.duplicate(), ItemScript.EquipSlot.HEAD)
	_check(helm_ok and diver.get_equipped_breather() == null,
		"a helm equips without becoming a breather")
	_check(helm_ok and diver.get_equipment_armor() >= int(helm.armor_value),
		"the helm's armor line is live (helms stay active underwater)")
	var reed_ok: bool = diver.equip_direct(reed.duplicate(), ItemScript.EquipSlot.BREATHER)
	_check(reed_ok and diver.get_equipped_breather() != null
		and str(diver.get_equipped_breather().id) == "acc_breather_reed",
		"the breather occupies its own layer beside the helm")

	var inv_svc = root.get_node_or_null("InventoryService")
	var ocean = root.get_node_or_null("OceanService")
	if inv_svc != null and ocean != null:
		inv_svc.register_inventory("capacity_diver", diver)
		var profile: Dictionary = ocean.breather_for("capacity_diver")
		_check(absf(float(profile.get("mult", 0.0)) - 2.0) < 0.0001,
			"OceanService reads the separate BREATHER layer")
		inv_svc.unregister_inventory("capacity_diver")
	else:
		_check(false, "OceanService + InventoryService autoloads are present")

	# A legacy necklace breather migrates to the new layer on load.
	var legacy_breather = load("res://data/accessories/acc_breather_abyss_pearl.tres")
	var saved := {
		"inventory": [],
		"equipment": {
			str(ItemScript.EquipSlot.NECKLACE): legacy_breather.to_dict()
		}
	}
	var restored: InventoryComponent = InventoryScript.from_dict(saved)
	_check(restored.get_equipped(ItemScript.EquipSlot.BREATHER) != null
		and restored.get_equipped(ItemScript.EquipSlot.NECKLACE) == null,
		"a legacy necklace breather migrates to BREATHER on load")

	# Lowering capacity later spills overflow into the bag, never deletes it.
	var overflow_saved := {
		"inventory": [null],
		"equipment": {
			str(ItemScript.EquipSlot.RING_1): _ring("test_saved_ring_1").to_dict(),
			str(ItemScript.EquipSlot.RING_2): _ring("test_saved_ring_2").to_dict(),
			str(ItemScript.EquipSlot.RING_3): _ring("test_saved_ring_3").to_dict()
		}
	}
	var overflow: InventoryComponent = InventoryScript.from_dict(overflow_saved)
	_check(overflow.get_equipped(ItemScript.EquipSlot.RING_3) == null,
		"a save above the authored capacity drops the extra lane")
	_check(overflow.get_item(0) != null and str(overflow.get_item(0).id) == "test_saved_ring_3",
		"the overflowed ring lands in the bag instead of vanishing")

	# --- D. Starter tablet -----------------------------------------------
	var tablet = load("res://data/accessories/acc_tablet_wayfarer.tres")
	_check(tablet != null, "the Wayfarer tablet record loads")
	if tablet != null:
		_check(tablet.is_tablet(), "the starter tablet is TABLET equipment")
		_check(bool(tablet.soulbound) and bool(tablet.unique),
			"the starter tablet is soulbound and unique")
		_check(tablet.is_loss_protected(),
			"the soulbound tablet is protected from sale/drop/loot")
		_check(int(tablet.max_durability) == 0,
			"the starter tablet cannot break into a tabletless state")
		var starter := _bag(1)
		starter.add_item(_ring("test_full_bag_ring"))
		var grant_ok: bool = starter.equip_direct(tablet.duplicate(),
			ItemScript.EquipSlot.TABLET)
		_check(grant_ok and starter.has_tablet(),
			"the starter tablet equips directly even with a full bag")
		_check(starter.get_world_ward("deep") > 0.0,
			"the equipped starter tablet guards the deep")

	# The world-entry backstop, even with every bag slot occupied.
	var backstop_inv = root.get_node_or_null("InventoryService")
	var kit_svc = root.get_node_or_null("StarterKitService")
	if backstop_inv != null and kit_svc != null:
		var tabletless := _bag(1)
		tabletless.add_item(_ring("test_bag_filler"))
		backstop_inv.register_inventory("tabletless_probe", tabletless)
		kit_svc.ensure_tablet("tabletless_probe")
		_check(tabletless.has_tablet()
			and tabletless.get_equipped_tablet() != null,
			"the world-entry backstop grants and equips a tablet with a full bag")
		backstop_inv.unregister_inventory("tabletless_probe")
	else:
		_check(false, "StarterKitService + InventoryService autoloads are present")

	var ds = root.get_node_or_null("DataService")
	if ds != null:
		var kits = ds.get_starter_kits()
		_check(kits != null and kits.guaranteed_for_all().has("acc_tablet_wayfarer"),
			"every starter role inherits the guaranteed tablet")
	else:
		_check(false, "DataService is present")
