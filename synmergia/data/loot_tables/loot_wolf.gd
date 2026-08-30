## LootTable factory for Grey Wolf
class_name LootWolf
extends RefCounted

static func create() -> LootTable:
	var t := LootTable.new()
	t.id = "loot_wolf"
	t.name = "Wolf Loot"
	t.description = "Drops from Grey Wolf enemies"
	t.level = 3
	t.min_items_dropped = 1
	t.max_items_dropped = 3

	t.add_entry("potion_health_small", 1, 2, 0.3)
	t.add_entry("soul_gem", 1, 1, 0.05, 2.0)
	t.add_entry("misc_ancient_coin", 3, 8, 0.8)
	t.add_currency("gold", 2, 8, 0.9)
	return t
