## AuraComponent - Buff/debuff and aura management
## Attached to entities that can have effects
extends Node
class_name AuraComponent
const Buff = preload("res://core/combat/buff.gd")
const StatusEffect = preload("res://core/entities/status_effect.gd")
const AuraBuffScript = preload("res://core/combat/aura_buff.gd")

## Runtime autoload lookup (script-mode-safe; mirrors
## inventory_component._resolve_service -- the bare identifier fails
## compile when autoloads are absent).
func _hub() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("EventHub")) if tree and tree.root else null

func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null


signal buff_added(buff: Buff)
signal buff_removed(buff: Buff)
signal debuff_added(debuff: StatusEffect)
signal debuff_removed(debuff: StatusEffect)
signal aura_activated(aura: AuraBuffScript)
signal aura_deactivated(aura: AuraBuffScript)

# Untyped mirrors: they hold whatever the canonical store holds
# (plain StatusEffects from skill.applyDoT AND Buff instances), and
# typed arrays would reject the plain-StatusEffect half at runtime.
var _active_buffs: Array = []
var _active_debuffs: Array = []
var _active_auras: Array[AuraBuffScript] = []

@export var max_buffs: int = 32
@export var max_debuffs: int = 16

func _ready() -> void:
	pass

## Live-path mirror tracking (R28). Entity owns the canonical
## status_effects store (its tick janitor sweeps it; StatusEffect
## self-manages timing); this classifies each applied effect for
## queries/dispels and fires the EventHub signals the HUD consumes.
## NO timing here: DURATION/TICKED effects run their own Timers -- a
## frame-advance on the mirror would double-drain them.
func track_effect(effect) -> void:
	if effect == null or not is_instance_valid(effect):
		return
	if effect.effect_type == StatusEffect.EffectType.BUFF:
		if _active_buffs.size() >= max_buffs:
			_active_buffs.pop_at(0)
		_active_buffs.append(effect)
		buff_added.emit(effect)
		var evt := _hub()
		if evt:
			evt.emit_signal("buff_applied", get_parent(), effect, effect.source)
		_emit_hub_effect_added(effect)
	elif effect.effect_type == StatusEffect.EffectType.DEBUFF:
		if _active_debuffs.size() >= max_debuffs:
			_active_debuffs.pop_at(0)
		_active_debuffs.append(effect)
		debuff_added.emit(effect)
		var evt := _hub()
		if evt:
			evt.emit_signal("debuff_applied", get_parent(), effect, effect.source)
		_emit_hub_effect_added(effect)

## Mirror untrack (called by Entity on every canonical removal).
func untrack_effect(effect) -> void:
	if effect == null:
		return
	if _active_buffs.has(effect):
		_active_buffs.erase(effect)
		buff_removed.emit(effect)
		var evt := _hub()
		if evt:
			evt.emit_signal("buff_removed", get_parent(), effect)
		_emit_hub_effect_removed(effect)
	elif _active_debuffs.has(effect):
		_active_debuffs.erase(effect)
		debuff_removed.emit(effect)
		var evt := _hub()
		if evt:
			evt.emit_signal("debuff_removed", get_parent(), effect)
		_emit_hub_effect_removed(effect)

## EventHub.entity_effect_added payload: a plain snapshot Dictionary
## keyed the way target_frame.gd reads it (id/name/description/
## is_debuff/remaining/stack/icon_path). The UI never holds the live
## StatusEffect, and orphan components (no canonical parent) stay silent.
func _emit_hub_effect_added(effect) -> void:
	var parent = get_parent()
	if parent == null or not ("entity_id" in parent):
		return
	var evt := _hub()
	if evt:
		evt.emit_signal("entity_effect_added", parent.entity_id, {
		"id": effect.effect_id,
		"name": effect.effect_name,
		"description": effect.description,
		"is_debuff": effect.effect_type == StatusEffect.EffectType.DEBUFF,
		"remaining": effect.remaining_duration,
		"stack": effect.current_stacks,
		"icon_path": effect.icon_path,
	})

func _emit_hub_effect_removed(effect) -> void:
	var parent = get_parent()
	if parent == null or not ("entity_id" in parent):
		return
	var evt := _hub()
	if evt:
		evt.emit_signal("entity_effect_removed", parent.entity_id, effect.effect_id)

## Add a buff. Delegates to the parent's canonical apply_status_effect
## (single store; the component mirrors via track_effect). The direct
## fallback covers orphan components with no canonical owner.
func add_buff(buff, source: Entity = null) -> bool:
	if buff == null:
		return false
	var parent = get_parent()
	if parent != null and parent.has_method("apply_status_effect"):
		if buff.source == null and source != null:
			buff.source = source
		parent.apply_status_effect(buff)
		return true

	# Check max buffs
	if _active_buffs.size() >= max_buffs:
		# Remove oldest buff
		remove_buff(_active_buffs[0])

	# Set source if not set
	if buff.source == null and source != null:
		buff.source = source

	_active_buffs.append(buff)

	buff.apply(parent)
	buff_added.emit(buff)
	var evt := _hub()
	if evt:
		evt.emit_signal("buff_applied", parent, buff, source)

	return true

## Remove a buff (canonical removal when an owner exists: it untracks
## and fires both signal sets; direct fallback for orphan components)
func remove_buff(buff) -> void:
	if not _active_buffs.has(buff):
		return
	var parent = get_parent()
	if parent != null and parent.has_method("remove_status_effect"):
		parent.remove_status_effect(buff)
		return

	buff.remove(parent)
	_active_buffs.erase(buff)

	buff_removed.emit(buff)
	var evt := _hub()
	if evt:
		evt.emit_signal("buff_removed", parent, buff)

## Add a debuff (same canonical delegation as add_buff)
func add_debuff(debuff, source: Entity = null) -> bool:
	if debuff == null:
		return false
	var parent = get_parent()
	if parent != null and parent.has_method("apply_status_effect"):
		if debuff.source == null and source != null:
			debuff.source = source
		parent.apply_status_effect(debuff)
		return true

	# Check max debuffs
	if _active_debuffs.size() >= max_debuffs:
		# Remove oldest debuff
		remove_debuff(_active_debuffs[0])

	# Set source if not set
	if debuff.source == null and source != null:
		debuff.source = source

	_active_debuffs.append(debuff)

	debuff.apply(parent)
	debuff_added.emit(debuff)
	var evt := _hub()
	if evt:
		evt.emit_signal("debuff_applied", parent, debuff, source)

	return true

## Remove a debuff (canonical removal when an owner exists; the old
## direct path emitted buff_removed for a debuff -- fixed below)
func remove_debuff(debuff) -> void:
	if not _active_debuffs.has(debuff):
		return
	var parent = get_parent()
	if parent != null and parent.has_method("remove_status_effect"):
		parent.remove_status_effect(debuff)
		return

	debuff.remove(parent)
	_active_debuffs.erase(debuff)

	debuff_removed.emit(debuff)
	var evt := _hub()
	if evt:
		evt.emit_signal("debuff_removed", parent, debuff)

## Add an aura (toggleable buff)
func add_aura(aura: AuraBuffScript, source: Entity = null) -> bool:
	if not aura:
		return false

	if aura.source == null and source != null:
		aura.source = source

	_active_auras.append(aura)

	aura.apply(get_parent())
	aura_activated.emit(aura)
	var evt := _hub()
	if evt:
		evt.emit_signal("aura_activated", get_parent(), aura)

	return true

## Remove an aura
func remove_aura(aura: AuraBuffScript) -> void:
	if not _active_auras.has(aura):
		return

	aura.remove(get_parent())
	_active_auras.erase(aura)

	aura_deactivated.emit(aura)
	var evt := _hub()
	if evt:
		evt.emit_signal("aura_deactivated", get_parent(), aura)

## Toggle an aura on/off
func toggle_aura(aura: AuraBuffScript, enabled: bool) -> void:
	if enabled:
		if not _active_auras.has(aura):
			add_aura(aura)
		aura.apply(get_parent())
	else:
		aura.remove(get_parent())

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
func get_all_buffs() -> Array:
	return _active_buffs.duplicate()

## Get all active debuffs
func get_all_debuffs() -> Array:
	return _active_debuffs.duplicate()

## Get all active auras
func get_all_auras() -> Array[AuraBuffScript]:
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

	var cat_enum: int = _get_category_enum(category)
	for debuff in _active_debuffs:
		if cat_enum >= 0 and debuff.effect_category == cat_enum:
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

## Get stat modifiers from all active buffs. Buff carries typed export
## fields (strength_bonus etc.), not a stat_modifiers dict -- the old
## read crashed on the first buff.
func get_stat_modifiers() -> Dictionary:
	var modifiers: Dictionary = {}

	for buff in _active_buffs:
		if buff == null or not is_instance_valid(buff):
			continue
		for stat in ["strength", "agility", "intelligence", "vitality", "endurance", "wisdom"]:
			var prop: String = stat + "_bonus"
			if prop in buff:
				modifiers[stat] = int(modifiers.get(stat, 0)) + int(buff.get(prop))

	return modifiers

## Timing note: this component runs NO per-frame loop. DURATION/TICKED
## effects own their Timers and the tick janitor sweeps expiry -- a
## frame-advance on the mirror list double-drained every debuff.

## Count buffs/debuffs
func get_buff_count() -> int:
	return _active_buffs.size()

func get_debuff_count() -> int:
	return _active_debuffs.size()

## Effect categories for dispel

## Convert category string to enum
func _get_category_enum(category: String) -> int:
	for key: String in StatusEffect.EffectCategory.keys():
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
		StatusEffect.EffectCategory.POISON, StatusEffect.EffectCategory.CURSE
	], caster)

## Internal dispel by categories. Collect first, then remove:
## remove_debuff mutates _active_debuffs, and erasing during for-in
## iteration skips elements.
func _dispel_by_category(categories: Array[int], caster: Entity = null) -> int:
	var dispelled := 0

	var debuffs_to_remove := []
	for debuff in _active_debuffs:
		if _can_dispel_effect(debuff, categories) and _check_dispel_resist(debuff, caster):
			debuffs_to_remove.append(debuff)
	for debuff in debuffs_to_remove:
		remove_debuff(debuff)
		dispelled += 1
		var evt := _hub()
		if evt:
			evt.emit_signal("effect_dispelled", get_parent(), debuff, caster)

	# Check auras (some auras are dispellable)
	var auras_to_remove := []
	for aura in _active_auras:
		if aura.is_dispellable and _matches_category(aura.effect_category, categories):
			auras_to_remove.append(aura)
	for aura in auras_to_remove:
		remove_aura(aura)
		dispelled += 1
		var evt := _hub()
		if evt:
			evt.emit_signal("aura_dispelled", get_parent(), aura, caster)

	return dispelled

## Check if effect can be dispelled by categories
func _can_dispel_effect(effect: StatusEffect, categories: Array[int]) -> bool:
	if not effect.is_dispellable:
		return false

	# StatusEffect's field is effect_category (the old `.category` read
	# crashed with a nonexistent-property error on the first dispel).
	return _matches_category(effect.effect_category, categories)

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
	if effect.dispel_resist_chance > 0:
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
		var cat_name: String = str(StatusEffect.EffectCategory.keys()[debuff.effect_category])
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
