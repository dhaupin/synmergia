## AuraComponent - Buff/debuff and aura management
## Attached to entities that can have effects
extends Node
class_name AuraComponent
const Buff = preload("res://core/combat/buff.gd")
const StatusEffect = preload("res://core/entities/status_effect.gd")


signal buff_added(buff: Buff)
signal buff_removed(buff: Buff)
signal debuff_added(debuff: StatusEffect)
signal debuff_removed(debuff: StatusEffect)
signal aura_activated(aura: AuraBuff)
signal aura_deactivated(aura: AuraBuff)

var _active_buffs: Array[Buff] = []
var _active_debuffs: Array[StatusEffect] = []
var _active_auras: Array[AuraBuff] = []

@export var max_buffs: int = 32
@export var max_debuffs: int = 16

func _ready() -> void:
	pass

## Add a buff
func add_buff(buff: Buff, source: Entity = null) -> bool:
	if buff == null:
		return false
	
	# Check max buffs
	if _active_buffs.size() >= max_buffs:
		# Remove oldest buff
		remove_buff(_active_buffs[0])
	
	# Set source if not set
	if buff.source == null and source != null:
		buff.source = source
	
	_active_buffs.append(buff)
	
	buff.apply(get_parent())
	buff_added.emit(buff)
	EventHub.buff_applied.emit(get_parent(), buff, source)
	
	return true

## Remove a buff
func remove_buff(buff: Buff) -> void:
	if not _active_buffs.has(buff):
		return
	
	buff.remove()
	_active_buffs.erase(buff)
	
	buff_removed.emit(buff)
	EventHub.buff_removed.emit(get_parent(), buff)

## Add a debuff
func add_debuff(debuff: StatusEffect, source: Entity = null) -> bool:
	if debuff == null:
		return false
	
	# Check max debuffs
	if _active_debuffs.size() >= max_debuffs:
		# Remove oldest debuff
		remove_debuff(_active_debuffs[0])
	
	# Set source if not set
	if debuff.source == null and source != null:
		debuff.source = source
	
	_active_debuffs.append(debuff)
	
	debuff.apply(get_parent())
	debuff_added.emit(debuff)
	EventHub.debuff_applied.emit(get_parent(), debuff, source)
	
	return true

## Remove a debuff
func remove_debuff(debuff: StatusEffect) -> void:
	if not _active_debuffs.has(debuff):
		return
	
	debuff.remove()
	_active_debuffs.erase(debuff)
	
	debuff_removed.emit(debuff)
	EventHub.buff_removed.emit(get_parent(), debuff)

## Add an aura (toggleable buff)
func add_aura(aura: AuraBuff, source: Entity = null) -> bool:
	if not aura:
		return false
	
	if aura.source == null and source != null:
		aura.source = source
	
	_active_auras.append(aura)
	
	aura.apply(get_parent())
	aura_activated.emit(aura)
	EventHub.aura_activated.emit(get_parent(), aura)
	
	return true

## Remove an aura
func remove_aura(aura: AuraBuff) -> void:
	if not _active_auras.has(aura):
		return
	
	aura.remove()
	_active_auras.erase(aura)
	
	aura_deactivated.emit(aura)
	EventHub.aura_deactivated.emit(get_parent(), aura)

## Toggle an aura on/off
func toggle_aura(aura: AuraBuff, enabled: bool) -> void:
	if enabled:
		if not _active_auras.has(aura):
			add_aura(aura)
		aura.apply(get_parent())
	else:
		aura.remove()

## Check if has buff
func has_buff(effect_id: String) -> bool:
	for buff in _active_buffs:
		if buff.effect_id == effect_id:
			return true
	return false

## Check if has debuff
func has_debuff(debuff_type: String) -> bool:
	for debuff in _active_debuffs:
		if StatusEffect.EffectCategory.keys()[debuff.effect_category] == debuff_type:
			return true
	return false

## Get buff by ID
func get_buff(effect_id: String) -> Buff:
	for buff in _active_buffs:
		if buff.effect_id == effect_id:
			return buff
	return null

## Get all active buffs
func get_all_buffs() -> Array[Buff]:
	return _active_buffs.duplicate()

## Get all active debuffs
func get_all_debuffs() -> Array[StatusEffect]:
	return _active_debuffs.duplicate()

## Get all active auras
func get_all_auras() -> Array[AuraBuff]:
	return _active_auras.duplicate()

## Dispel buffs by category
func dispel_buffs(category: String) -> int:
	var removed := 0
	var buffs_to_remove := []
	
	for buff in _active_buffs:
		var cat_enum := _get_category_enum(category)
		if cat_enum >= 0 and buff.effect_category == cat_enum:
			buffs_to_remove.append(buff)
	
	for buff in buffs_to_remove:
		remove_buff(buff)
		removed += 1
	
	return removed

## Dispel debuffs by category
func dispel_debuffs(category: String) -> int:
	var removed := 0
	var debuffs_to_remove := []
	
	for debuff in _active_debuffs:
		if debuff.effect_category == category:
			debuffs_to_remove.append(debuff)
	
	for debuff in debuffs_to_remove:
		remove_debuff(debuff)
		removed += 1
	
	return removed

## Clear all buffs
func clear_buffs() -> void:
	var buffs := _active_buffs.duplicate()
	for buff in buffs:
		remove_buff(buff)

## Clear all debuffs
func clear_debuffs() -> void:
	var debuffs := _active_debuffs.duplicate()
	for debuff in debuffs:
		remove_debuff(debuff)

## Clear all effects
func clear_all() -> void:
	clear_buffs()
	clear_debuffs()
	
	var auras := _active_auras.duplicate()
	for aura in auras:
		remove_aura(aura)

## Get stat modifiers from all active buffs
func get_stat_modifiers() -> Dictionary:
	var modifiers: Dictionary = {}
	
	for buff in _active_buffs:
		for stat in buff.stat_modifiers:
			if not modifiers.has(stat):
				modifiers[stat] = 0
			modifiers[stat] += buff.stat_modifiers[stat]
	
	return modifiers

## Process physics (for DOTs, etc.)
func _physics_process(delta: float) -> void:
	# Process DOTs
		if debuff is DamageOverTime:
			debuff.tick(delta)

## Count buffs/debuffs
func get_buff_count() -> int:
	return _active_buffs.size()

func get_debuff_count() -> int:
	return _active_debuffs.size()

## Effect categories for dispel

## Convert category string to enum
func _get_category_enum(category: String) -> int:
	for key in StatusEffect.EffectCategory.keys():
		if key.to_lower() == category.to_lower():
			return StatusEffect.EffectCategory.get(key)
	return -1

## Dispel magic effects
func dispel_magic(caster: Entity = null) -> int:
	return _dispel_by_category([StatusEffect.EffectCategory.MAGIC, StatusEffect.EffectCategory.CURSE, StatusEffect.EffectCategory.POISON], caster)

## Dispel curses specifically
func dispel_curses(caster: Entity = null) -> int:
	return _dispel_by_category([StatusEffect.EffectCategory.CURSE], caster)

## Dispel poison/disease
func dispel_poison(caster: Entity = null) -> int:
	return _dispel_by_category([StatusEffect.EffectCategory.POISON], caster)

## Dispel all dispellable effects
func dispel_all(caster: Entity = null) -> int:
	return _dispel_by_category([
		StatusEffect.EffectCategory.MAGIC, StatusEffect.EffectCategory.CURSE, StatusEffect.EffectCategory.POISON,
		StatusEffect.EffectCategory.HOLY, StatusEffect.EffectCategory.SHADOW, StatusEffect.EffectCategory.FIRE,
		StatusEffect.EffectCategory.ICE, StatusEffect.EffectCategory.LIGHTNING, StatusEffect.EffectCategory.ARCANE
	], caster)

## Cleanse (removes debuffs, often player ability)
func cleanse(caster: Entity = null) -> int:
	return _dispel_by_category([
		StatusEffect.EffectCategory.POISON, StatusEffect.EffectCategory.DISEASE, StatusEffect.EffectCategory.CURSE
	], caster)

## Internal dispel by categories
func _dispel_by_category(categories: Array[int], caster: Entity = null) -> int:
	var dispelled := 0
	
	# Check debuffs
	for debuff in _active_debuffs:
		if _can_dispel_effect(debuff, categories):
			if _check_dispel_resist(debuff, caster):
				remove_debuff(debuff)
				dispelled += 1
				EventHub.effect_dispelled.emit(get_parent(), debuff, caster)
	
	# Check auras (some auras are dispellable)
	for aura in _active_auras:
		if aura.is_dispellable and _matches_category(aura.effect_category, categories):
			remove_aura(aura)
			dispelled += 1
			EventHub.aura_dispelled.emit(get_parent(), aura, caster)
	
	return dispelled

## Check if effect can be dispelled by categories
func _can_dispel_effect(effect: StatusEffect, categories: Array[int]) -> bool:
	if not effect.is_dispellable:
		return false
	
	return _matches_category(effect.category, categories)

## Check if effect category matches
func _matches_category(effect_category: int, dispel_categories: Array[int]) -> bool:
	# Special categories (BLEED, STUN, FEAR, CHARM) aren't general dispels
	var special_categories := [StatusEffect.EffectCategory.BLEED, StatusEffect.EffectCategory.STUN, StatusEffect.EffectCategory.FEAR, StatusEffect.EffectCategory.CHARM]
	if special_categories.has(effect_category):
		return dispel_categories.has(effect_category)
	
	# Magic, curse, poison are general dispel targets
	return dispel_categories.has(StatusEffect.EffectCategory.MAGIC) or dispel_categories.has(effect_category)

## Check if dispel succeeds (some effects have resist chance)
func _check_dispel_resist(effect: StatusEffect, caster: Entity) -> bool:
	if caster == null:
		return true  # No resist if no caster
	
	# Boss effects might resist
	if effect. dispel_resist_chance > 0:
		return randf() > effect.dispel_resist_chance
	
	return true

## Check if entity has specific category of effects
func has_category(category: int) -> bool:
	for debuff in _active_debuffs:
		if debuff.effect_category == category:
			return true
	return false

## Get all effects of category
func get_effects_by_category(category: int) -> Array[StatusEffect]:
	var effects: Array[StatusEffect] = []
	for debuff in _active_debuffs:
		if debuff.effect_category == category:
			effects.append(debuff)
	return effects

## Get dispel info for UI
func get_dispel_info() -> Dictionary:
	var categories: Dictionary = {}
	
	for debuff in _active_debuffs:
		var cat_name := StatusEffect.EffectCategory.keys()[debuff.effect_category]
		if not categories.has(cat_name):
			categories[cat_name] = []
		categories[cat_name].append({
			"name": debuff.effect_name,
			"dispellable": debuff.is_dispellable,
			"duration": debuff.get_remaining_duration() if "duration_remaining" in debuff else -1
		})
	
	return {
		"debuff_count": _active_debuffs.size(),
		"categories": categories
	}
