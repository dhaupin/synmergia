## AuraComponent - Buff/debuff and aura management
## Attached to entities that can have effects
class_name AuraComponent
extends Node

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
func add_buff(buff: Buff, source: SynmergiaEntity = null) -> bool:
	if buff == null:
		return false
	
	# Check max buffs
	if _active_buffs.size() >= max_buffs:
		# Remove oldest buff
		remove_buff(_active_buffs[0])
	
	# Set source if not set
	if buff.source == null and source != null:
		buff.source = source
	
	buff.target_entity = get_parent()
	_active_buffs.append(buff)
	
	buff.start()
	buff_added.emit(buff)
	EventBus.buff_applied.emit(get_parent(), buff, source)
	
	return true

## Remove a buff
func remove_buff(buff: Buff) -> void:
	if not _active_buffs.has(buff):
		return
	
	buff.stop()
	_active_buffs.erase(buff)
	
	buff_removed.emit(buff)
	EventBus.buff_removed.emit(get_parent(), buff)

## Add a debuff
func add_debuff(debuff: StatusEffect, source: SynmergiaEntity = null) -> bool:
	if debuff == null:
		return false
	
	# Check max debuffs
	if _active_debuffs.size() >= max_debuffs:
		# Remove oldest debuff
		remove_debuff(_active_debuffs[0])
	
	# Set source if not set
	if debuff.source == null and source != null:
		debuff.source = source
	
	debuff.target_entity = get_parent()
	_active_debuffs.append(debuff)
	
	debuff.start()
	debuff_added.emit(debuff)
	EventBus.debuff_applied.emit(get_parent(), debuff, source)
	
	return true

## Remove a debuff
func remove_debuff(debuff: StatusEffect) -> void:
	if not _active_debuffs.has(debuff):
		return
	
	debuff.stop()
	_active_debuffs.erase(debuff)
	
	debuff_removed.emit(debuff)
	EventBus.buff_removed.emit(get_parent(), debuff)

## Add an aura (toggleable buff)
func add_aura(aura: AuraBuff, source: SynmergiaEntity = null) -> bool:
	if not aura:
		return false
	
	if aura.source == null and source != null:
		aura.source = source
	
	aura.target_entity = get_parent()
	_active_auras.append(aura)
	
	aura.start()
	aura_activated.emit(aura)
	EventBus.aura_activated.emit(get_parent(), aura)
	
	return true

## Remove an aura
func remove_aura(aura: AuraBuff) -> void:
	if not _active_auras.has(aura):
		return
	
	aura.stop()
	_active_auras.erase(aura)
	
	aura_deactivated.emit(aura)
	EventBus.aura_deactivated.emit(get_parent(), aura)

## Toggle an aura on/off
func toggle_aura(aura: AuraBuff, enabled: bool) -> void:
	if enabled:
		if not _active_auras.has(aura):
			add_aura(aura)
		aura.activate()
	else:
		aura.deactivate()

## Check if has buff
func has_buff(buff_id: String) -> bool:
	for buff in _active_buffs:
		if buff.buff_id == buff_id:
			return true
	return false

## Check if has debuff
func has_debuff(debuff_type: String) -> bool:
	for debuff in _active_debuffs:
		if debuff.status_type == debuff_type:
			return true
	return false

## Get buff by ID
func get_buff(buff_id: String) -> Buff:
	for buff in _active_buffs:
		if buff.buff_id == buff_id:
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
		if buff.category == category:
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
		if debuff.category == category:
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
	for debuff in _active_debuffs:
		if debuff is DamageOverTime:
			debuff.tick(delta)

## Count buffs/debuffs
func get_buff_count() -> int:
	return _active_buffs.size()

func get_debuff_count() -> int:
	return _active_debuffs.size()

## Effect categories for dispel
enum EffectCategory {
	MAGIC,      # General magic effects
	CURSE,      # Curses and hexes
	POISON,     # Poison and disease
	PHYSICAL,   # Physical debuffs
	HOLY,       # Holy/light effects
	SHADOW,     # Shadow/dark effects
	FIRE,       # Fire effects
	ICE,        # Frost effects
	LIGHTNING,  # Lightning effects
	ARCANE,     # Arcane effects
	BLEED,      # Bleeding effects
	STUN,       # Stun effects
	FEAR,       # Fear effects
	CHARM       # Charm effects
}

## Dispel magic effects
func dispel_magic(caster: SynmergiaEntity = null) -> int:
	return _dispel_by_category([EffectCategory.MAGIC, EffectCategory.CURSE, EffectCategory.POISON], caster)

## Dispel curses specifically
func dispel_curses(caster: SynmergiaEntity = null) -> int:
	return _dispel_by_category([EffectCategory.CURSE], caster)

## Dispel poison/disease
func dispel_poison(caster: SynmergiaEntity = null) -> int:
	return _dispel_by_category([EffectCategory.POISON], caster)

## Dispel all dispellable effects
func dispel_all(caster: SynmergiaEntity = null) -> int:
	return _dispel_by_category([
		EffectCategory.MAGIC, EffectCategory.CURSE, EffectCategory.POISON,
		EffectCategory.HOLY, EffectCategory.SHADOW, EffectCategory.FIRE,
		EffectCategory.ICE, EffectCategory.LIGHTNING, EffectCategory.ARCANE
	], caster)

## Cleanse (removes debuffs, often player ability)
func cleanse(caster: SynmergiaEntity = null) -> int:
	return _dispel_by_category([
		EffectCategory.POISON, EffectCategory.DISEASE, EffectCategory.CURSE
	], caster)

## Internal dispel by categories
func _dispel_by_category(categories: Array[int], caster: SynmergiaEntity = null) -> int:
	var dispelled := 0
	
	# Check debuffs
	for debuff in _active_debuffs:
		if _can_dispel_effect(debuff, categories):
			if _check_dispel_resist(debuff, caster):
				remove_debuff(debuff)
				dispelled += 1
				EventBus.effect_dispelled.emit(get_parent(), debuff, caster)
	
	# Check auras (some auras are dispellable)
	for aura in _active_auras:
		if aura.is_dispellable and _matches_category(aura.category, categories):
			remove_aura(aura)
			dispelled += 1
			EventBus.aura_dispelled.emit(get_parent(), aura, caster)
	
	return dispelled

## Check if effect can be dispelled by categories
func _can_dispel_effect(effect: StatusEffect, categories: Array[int]) -> bool:
	if not effect.is_dispellable:
		return false
	
	return _matches_category(effect.category, categories)

## Check if effect category matches
func _matches_category(effect_category: int, dispel_categories: Array[int]) -> bool:
	# Special categories (BLEED, STUN, FEAR, CHARM) aren't general dispels
	var special_categories := [EffectCategory.BLEED, EffectCategory.STUN, EffectCategory.FEAR, EffectCategory.CHARM]
	if special_categories.has(effect_category):
		return dispel_categories.has(effect_category)
	
	# Magic, curse, poison are general dispel targets
	return dispel_categories.has(EffectCategory.MAGIC) or dispel_categories.has(effect_category)

## Check if dispel succeeds (some effects have resist chance)
func _check_dispel_resist(effect: StatusEffect, caster: SynmergiaEntity) -> bool:
	if caster == null:
		return true  # No resist if no caster
	
	# Boss effects might resist
	if effect. dispel_resist_chance > 0:
		return randf() > effect.dispel_resist_chance
	
	return true

## Check if entity has specific category of effects
func has_category(category: int) -> bool:
	for debuff in _active_debuffs:
		if debuff.category == category:
			return true
	return false

## Get all effects of category
func get_effects_by_category(category: int) -> Array[StatusEffect]:
	var effects: Array[StatusEffect] = []
	for debuff in _active_debuffs:
		if debuff.category == category:
			effects.append(debuff)
	return effects

## Get dispel info for UI
func get_dispel_info() -> Dictionary:
	var categories: Dictionary = {}
	
	for debuff in _active_debuffs:
		var cat_name := EffectCategory.keys()[debuff.category]
		if not categories.has(cat_name):
			categories[cat_name] = []
		categories[cat_name].append({
			"name": debuff.display_name,
			"dispellable": debuff.is_dispellable,
			"duration": debuff.duration_remaining if "duration_remaining" in debuff else -1
		})
	
	return {
		"debuff_count": _active_debuffs.size(),
		"categories": categories
	}
