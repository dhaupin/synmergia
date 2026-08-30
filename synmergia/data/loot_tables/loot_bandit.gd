## LootTable factory for Bandit
class_name LootBandit
extends RefCounted

static func create() -> LootTable:
	var t := LootTable.new()
	t.id = "loot_bandit"
	t.name = "Bandit Loot"
	t.description = "Drops from Bandit enemies"
	t.level = 5
	t.min_items_dropped = 1
	t.max_items_dropped = 4

	t.add_entry("potion_health_small", 1, 3, 0.4)
	t.add_entry("misc_ancient_coin", 5, 15, 0.7)
	t.add_entry("wep_iron_sword", 1, 1, 0.1)
	t.add_entry("arm_leather_chest", 1, 1, 0.05)
	t.add_currency("gold", 5, 20, 0.9)
	return t
