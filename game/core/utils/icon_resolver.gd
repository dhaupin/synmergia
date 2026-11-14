## IconResolver - Centralized icon/texture resolution for all game entities
extends RefCounted

## Category placeholder base path
const BASE := "res://ui/textures"

## Item category -> placeholder path
const ITEM_ICONS: Dictionary = {
	0: "%s/items/weapon.png" % BASE,      # WEAPON
	1: "%s/items/armor.png" % BASE,       # ARMOR
	2: "%s/items/accessory.png" % BASE,   # ACCESSORY
	3: "%s/items/consumable.png" % BASE,  # CONSUMABLE
	4: "%s/items/resource.png" % BASE,     # RESOURCE
	5: "%s/items/gem.png" % BASE,         # GEM
	6: "%s/items/event.png" % BASE,       # EVENT
	7: "%s/items/furnishing.png" % BASE,    # FURNISHING
	8: "%s/items/skill_book.png" % BASE,  # SKILL_BOOK
	9: "%s/items/misc.png" % BASE,        # MISC
}

## Skill type -> placeholder path
const SKILL_ICONS: Dictionary = {
	0: "%s/items/weapon.png" % BASE,   # MELEE
	1: "%s/items/weapon.png" % BASE,   # RANGED
	2: "%s/items/misc.png" % BASE,     # INSTANT
	3: "%s/items/misc.png" % BASE,     # GROUND_TARGETED
	4: "%s/items/misc.png" % BASE,     # TARGETED_AOE
	5: "%s/items/misc.png" % BASE,     # SELF
	6: "%s/items/misc.png" % BASE,     # CHANNEL
	7: "%s/items/misc.png" % BASE,     # PROJECTILE_AOE
	8: "%s/items/misc.png" % BASE,     # REVIVE
}

## Entity fallback icons
const ENEMY_ICON := "%s/enemies/default.png" % BASE
const NPC_ICON := "%s/npcs/default.png" % BASE

## ============================================================================
## ITEM ICONS
## ============================================================================

static func get_item_icon(item: Resource) -> Texture2D:
	if item == null:
		return _fallback()
	var path: String = str(_prop(item, "icon_path", ""))
	if not path.is_empty() and _tex(path):
		return _tex(path)
	return _item_category_icon(_prop(item, "item_category", 9))

static func get_item_icon_from_dict(data: Dictionary) -> Texture2D:
	if data.is_empty():
		return _fallback()
	# Try direct or nested icon_path
	var path: String = str(data.get("icon_path", ""))
	if path.is_empty():
		var nested = data.get("data", {})
		if nested is Dictionary:
			path = nested.get("icon_path", "")
	if not path.is_empty() and _tex(path):
		return _tex(path)
	return _item_category_icon(data.get("item_category", 9))


## ============================================================================
## SKILL ICONS
## ============================================================================

static func get_skill_icon(skill: Resource) -> Texture2D:
	if skill == null:
		return _fallback()
	var path: String = str(_prop(skill, "icon_path", ""))
	if not path.is_empty() and _tex(path):
		return _tex(path)
	return _skill_type_icon(_prop(skill, "skill_type", 0))

static func get_skill_icon_from_dict(data: Dictionary) -> Texture2D:
	if data.is_empty():
		return _fallback()
	var path: String = str(data.get("icon_path", ""))
	if not path.is_empty() and _tex(path):
		return _tex(path)
	return _skill_type_icon(data.get("skill_type", 0))


## ============================================================================
## ENTITY ICONS
## ============================================================================

static func get_npc_icon(npc: Resource) -> Texture2D:
	if npc == null:
		return _tex(NPC_ICON)
	var path: String = str(_prop(npc, "icon_path", ""))
	if not path.is_empty() and _tex(path):
		return _tex(path)
	return _tex(NPC_ICON)

static func get_enemy_icon(enemy: Resource) -> Texture2D:
	if enemy == null:
		return _tex(ENEMY_ICON)
	var path: String = str(_prop(enemy, "icon_path", ""))
	if not path.is_empty() and _tex(path):
		return _tex(path)
	return _tex(ENEMY_ICON)


## ============================================================================
## GENERIC
## ============================================================================

static func get_icon_for_path(path: String, fallback: Texture2D = null) -> Texture2D:
	if not path.is_empty() and _tex(path):
		return _tex(path)
	return fallback if fallback else _fallback()


## ============================================================================
## INTERNAL
## ============================================================================

static func _prop(res: Resource, key: String, default) -> Variant:
	if res == null:
		return default
	# Resource has no has() method (that's Dictionary/Array); the old
	# res.has(key) script-errored every call, so the ternary aborted and
	# returned null instead of `default` -- producing "res://<null>"
	# loads and Nil-to-int category conversions downstream. `key in res`
	# is the object property existence check.
	return res.get(key) if key in res else default

static func _tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var t := load(path)
	if t is Texture2D:
		return t
	return null

static func _fallback() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.4, 0.4, 0.4, 1.0))
	return ImageTexture.create_from_image(img)

static func _item_category_icon(cat: int) -> Texture2D:
	var t := _tex(ITEM_ICONS.get(cat, ITEM_ICONS[9]))
	return t if t != null else _fallback()

static func _skill_type_icon(t: int) -> Texture2D:
	var s := _tex(SKILL_ICONS.get(t, SKILL_ICONS[2]))
	return s if s != null else _fallback()

## Faction relation icon (hostile/friendly/neutral or raw color key).
## Falls back to the generic icon when no faction art is registered.
static func get_faction_icon(relation: String) -> Texture2D:
	var rel: String = relation.to_lower()
	for rel_key in ["hostile", "enemy", "friendly", "ally", "neutral"]:
		if rel == rel_key or (rel_key == "enemy" and rel == "hostile") or (rel_key == "ally" and rel == "friendly"):
			var tex := _tex("res://assets/icons/factions/%s.png" % rel)
			if tex:
				return tex
	return _fallback()


## Status-effect icon for effect dictionaries (buff bar / target frame).
static func get_effect_icon_from_dict(data: Dictionary) -> Texture2D:
	if data.is_empty():
		return _fallback()
	# Explicit icon path wins.
	var path: String = str(data.get("icon_path", ""))
	if path.is_empty():
		var nested = data.get("data", {})
		if nested is Dictionary:
			path = str((nested as Dictionary).get("icon_path", ""))
	if not path.is_empty():
		var tex := _tex(path)
		if tex:
			return tex
	# Buff vs debuff default art
	var is_debuff: bool = bool(data.get("is_debuff", false))
	if is_debuff:
		return _tex("res://assets/icons/effects/debuff_default.png") if _tex("res://assets/icons/effects/debuff_default.png") else _fallback()
	return _tex("res://assets/icons/effects/buff_default.png") if _tex("res://assets/icons/effects/buff_default.png") else _fallback()
