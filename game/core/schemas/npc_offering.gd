## NPCOffering - What an NPC provides when the player interacts with them.
##
## This is NOT limited to stores — blacksmith repair, bank vault access, quest lines,
## and dialogue trees are all offerings. The type string is the discriminator;
## each .tres file declares its own type.
##
## data/npc_offerings/*.tres files define concrete offerings.
## NPCData.includes[] references them by {type: "offering", ref_id: "<id>"}.
##
## Offering types:
##   "vendor"   — buy/sell items for gold
##   "service"  — one-shot service (repair, respec, etc.)
##   "quest"    — quest list (available, turn-in)
##   "dialogue" — conversation tree
##   "bank"     — vault access
extends Resource
class_name NPCOffering

## The discriminator. Must be one of the type strings above.
@export var type: String = ""

## Human-readable name for the offering (shown in UI).
@export var display_name: String = ""

## ============================================================================
## VENDOR TYPE
## ============================================================================

## How the vendor stocks items.
## "by_category"  — filter DataService item DB by sell_categories
## "by_item_id"   — use only catalog_items list
## "mixed"        — union of both
@export var stock_mode: String = "by_category"

## Item categories this vendor sells (player buys from vendor).
## Array of ItemCategory enum values as integers.
## Used when stock_mode is "by_category" or "mixed".
@export var sell_categories: Array[int] = []

## Item categories this vendor buys from the player.
## Array of ItemCategory enum values as integers.
@export var buy_categories: Array[int] = []

## Explicit item list. Each entry: {item_id, qty, price_override}
## Used when stock_mode is "by_item_id" or "mixed".
@export var catalog_items: Array[Dictionary] = []

## Price multiplier applied on top of NPCData pricing.
@export var price_multiplier: float = 1.0

## Whether stock is unlimited. If false, stock is tracked per-item per-vendor.
@export var unlimited_stock: bool = true

## Default stock quantity per catalog item.
@export var stock_qty: int = 99

## When to restock limited-stock vendors.
## "close"   — full restock when player closes shop
## "daily"   — restock once per day
## "never"   — no automatic restock
@export var restock_trigger: String = "close"

## How much to restock. -1 = full restock to stock_qty.
@export var restock_amount: int = -1


## ============================================================================
## SERVICE TYPE
## ============================================================================

## Which service handles this offering. Maps to a service singleton name.
## e.g. "BlacksmithService", "SkillAcademyService"
@export var service_id: String = ""

## Optional parameters passed to the service.
@export var service_params: Dictionary = {}


## ============================================================================
## QUEST TYPE
## ============================================================================

## Quest IDs this NPC offers.
@export var quest_ids: Array[String] = []


## ============================================================================
## DIALOGUE TYPE
## ============================================================================

## Dialogue resource ID — maps to data/dialogues/<dialogue_id>.tres
@export var dialogue_id: String = ""

## Whether this dialogue can only be triggered once.
@export var one_shot: bool = false


## ============================================================================
## BANK TYPE
## ============================================================================

## Which vault type to open.
## "personal" | "guild" | "account"
@export var vault_type: String = "personal"


## ============================================================================
## HELPERS
## ============================================================================

func _get_category_names() -> Array[String]:
	var result: Array[String] = []
	var Item = load("res://core/schemas/item.gd")
	for cat_int in sell_categories:
		if cat_int < Item.ItemCategory.size():
			result.append(Item.ItemCategory.keys()[cat_int])
	return result

func get_display_categories() -> String:
	var names := _get_category_names()
	return ", ".join(names) if not names.is_empty() else "All items"
