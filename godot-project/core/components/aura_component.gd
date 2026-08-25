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
func add_aura(aura: AuraBuff, source: Entity = null) -> bool:
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
