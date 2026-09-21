## HealthComponent - HP management and death handling
## Attached to entities that have health
extends Node
class_name HealthComponent
const Item = preload("res://core/schemas/item.gd")
const Corpse = preload("res://scenes/entities/corpse.gd")


signal health_changed(current: int, maximum: int, delta: int)
signal health_depleted()
signal died(killer: Entity)
signal resurrecting(respawn_time: float)
signal respawned()

@export var max_health: int = 100
@export var base_health: int = 100
@export var health_regen: float = 1.0  # HP per second
@export var health_regen_combat: float = 0.0  # HP per second in combat

var current_health: int
var _is_dead: bool = false
var _respawn_timer: float = 0.0
var _respawn_time: float = 10.0
var _bind_position: Vector3 = Vector3.ZERO
var _killer: Node3D = null

func _ready() -> void:
	current_health = max_health

	# Connect death notification to EventBus
	health_depleted.connect(_on_health_depleted)

func _on_health_depleted() -> void:
	var entity: Node3D = get_parent()
	var killer_name := ""
	var killer_type := "monster"

	if _killer:
		killer_name = _killer.display_name
		if _killer is PlayerController:
			killer_type = "player"
		elif "faction_id" in _killer and "faction_id" in entity and _killer.faction_id != entity.faction_id:
			killer_type = "pvp"

	if NotificationService:
		NotificationService.notify_death(entity.entity_id, killer_name, killer_type)

		# Notify party members
		if entity.has_method("get_party_id"):
			var party_id = entity.get_party_id()
			if party_id != "":
				var party = PartyService.get_party(party_id) if PartyService else null
				if party:
					for member_id in party.get("members", []):
						NotificationService.notify_party_member_died(member_id, entity.display_name, killer_name)

## Take damage
func take_damage(amount: int, source: Entity = null, damage_type: String = "physical") -> int:
	if _is_dead:
		return 0

	# Check for interrupt (before applying damage). Owner may be any
	# combatant (Enemy, PlayerController); components are optional.
	var entity: Node3D = get_parent()
	if entity != null and "combat_component" in entity and entity.combat_component != null:
		entity.combat_component.on_damage_taken(amount, source, damage_type)

	# Apply armor/mitigation
	var mitigated: int = 0
	if entity != null and "inventory_component" in entity and entity.inventory_component != null:
		mitigated = entity.inventory_component.get_equipment_armor()
	var actual_damage: int = max(1, amount - mitigated)

	current_health = max(0, current_health - actual_damage)
	health_changed.emit(current_health, max_health, -actual_damage)

	# Emit combat events
	EventHub.damage_dealt.emit(source, get_parent(), actual_damage, damage_type)

	if current_health <= 0:
		die(source)

	return actual_damage

## Heal
func heal(amount: int, source: Entity = null) -> int:
	if _is_dead:
		return 0

	var actual_heal: int = min(amount, max_health - current_health)
	current_health += actual_heal
	health_changed.emit(current_health, max_health, actual_heal)

	return actual_heal

## Get percentage health
func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return float(current_health) / float(max_health)

## Is entity dead?
func is_dead() -> bool:
	return _is_dead


## Revive where we stand (no respawn-location change). Clears the dead
## flag and restores full health. RespawnService drives the full
## respawn flow; this lightweight variant is for in-place revives and
## drivers that need a live entity without a respawn cycle.
func revive_in_place() -> void:
	if not _is_dead and current_health > 0:
		return
	_is_dead = false
	_killer = null
	current_health = max_health

## Die
func die(killer: Node3D = null) -> void:
	if _is_dead:
		return

	_is_dead = true
	_killer = killer
	current_health = 0

	# Stop all combat state
	var entity: Node3D = get_parent()
	if entity != null and "combat_component" in entity and entity.combat_component != null:
		entity.combat_component.interrupt()

	# SECURITY: Cancel any active locks on death
	if entity.entity_id and PlayerLockService:
		PlayerLockService.cancel_on_death(entity.entity_id)
		# Also cancel follow
		if FollowService:
			FollowService.cancel_all_for_player(entity.entity_id)

	# Create corpse
	_create_corpse(killer)

	health_depleted.emit()
	EventHub.entity_died.emit(entity, killer, null)

	# Emit player-specific signals
	if entity is PlayerController:
		EventHub.player_died.emit(entity, killer)

	# Emit entity killed (for kill streak tracking)
	if killer:
		EventHub.entity_killed.emit(killer, entity, "physical")

		# Emit player_killed_player for PvP tracking
		if killer is PlayerController and entity is PlayerController:
			EventHub.player_killed_player.emit(killer, entity)

	# Start respawn timer
	_start_respawn()

## Create corpse entity
var _corpse: Corpse = null

func _create_corpse(killer: Node3D) -> void:
	var entity: Node3D = get_parent()

	# Try to load corpse scene if it exists
	var corpse_scene_path := "res://scenes/entities/corpse.tscn"
	var corpse_scene := load(corpse_scene_path)

	if corpse_scene:
		_corpse = corpse_scene.instantiate()
		get_tree().root.add_child(_corpse)
		_corpse.global_position = entity.global_position
		if _corpse.has_method("setup"):
			_corpse.setup(entity, killer)
		EventHub.corpse_created.emit(entity, _corpse, killer)
		GameLog.debug("HealthComponent: Created corpse at %s" % entity.global_position)
	else:
		GameLog.warn("HealthComponent: Corpse scene not found at %s" % corpse_scene_path)

## Remove corpse
func _remove_corpse() -> void:
	if _corpse:
		_corpse.queue_free()
		_corpse = null

## Set respawn location options
enum RespawnLocation {
	BIND_POINT,      # Last bound location
	NEAR_CORPSE,     # Near death location
	NEAR_PARTY,      # Near party members
	CUSTOM           # Specific location
}

@export var default_respawn_location: RespawnLocation = RespawnLocation.BIND_POINT
@export var respawn_location: Vector3 = Vector3.ZERO  # For CUSTOM

## Get available respawn locations
func get_respawn_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var entity: Node3D = get_parent()

	# Always available: Bind point
	options.append({
		"location": RespawnLocation.BIND_POINT,
		"name": "Bind Point",
		"position": _bind_position,
		"delay": 0
	})

	# Always available: Near corpse (if corpse exists)
	if _corpse:
		options.append({
			"location": RespawnLocation.NEAR_CORPSE,
			"name": "Near Corpse",
			"position": entity.global_position,
			"delay": _respawn_time * 0.5  # Faster respawn
		})

	return options

## Respawn at specific location
func respawn_at(location: RespawnLocation, custom_position: Vector3 = Vector3.ZERO) -> void:
	match location:
		RespawnLocation.BIND_POINT:
			_do_respawn_at(_bind_position)
		RespawnLocation.NEAR_CORPSE:
			var entity: Node3D = get_parent()
			_do_respawn_at(entity.global_position)
		RespawnLocation.CUSTOM:
			_do_respawn_at(custom_position)
		_:
			_do_respawn_at(_bind_position)

func _do_respawn_at(position: Vector3) -> void:
	_remove_corpse()
	_is_dead = false
	current_health = max_health

	var entity: Node3D = get_parent()
	entity.global_position = position

	respawned.emit()
	EventHub.entity_spawned.emit(entity, null)

## Start respawn process
func _start_respawn() -> void:
	_respawn_timer = _respawn_time
	resurrecting.emit(_respawn_time)

## Set respawn position
func set_bind_position(position: Vector3) -> void:
	_bind_position = position

## Get bind position
func get_bind_position() -> Vector3:
	return _bind_position

## Respawn immediately (admin/quest)
func force_respawn() -> void:
	_do_respawn()

func _process(delta: float) -> void:
	if _is_dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0:
			_do_respawn()
	else:
		# Health regen
		var regen := health_regen
		var entity: Node = get_parent()
		if entity and "combat_component" in entity and entity.combat_component and "in_combat" in entity.combat_component and entity.combat_component.in_combat:
			regen = health_regen_combat

		if regen > 0 and current_health < max_health:
			var heal_amount := int(regen * delta)
			if heal_amount > 0:
				current_health = mini(current_health + heal_amount, max_health)
				health_changed.emit(current_health, max_health, heal_amount)

	# Self-rez cooldown
	if _self_rez_cooldown > 0:
		_self_rez_cooldown -= delta

func _do_respawn() -> void:
	_is_dead = false
	current_health = max_health
	_respawn_timer = 0.0

	# Move to respawn position
	var entity: Node3D = get_parent()
	entity.global_position = _bind_position

	respawned.emit()
	EventHub.entity_spawned.emit(entity, null)

## Set max health
func set_max_health(new_max: int) -> void:
	var old_max := max_health
	max_health = new_max

	# Scale current health proportionally
	if old_max > 0:
		current_health = int(float(current_health) / old_max * max_health)

	health_changed.emit(current_health, max_health, 0)

## Get corpse reference (if exists)
func get_corpse() -> Corpse:
	return _corpse

## Check if corpse exists
func has_corpse() -> bool:
	return _corpse != null

## Get corpse loot info for UI
func get_corpse_loot_info() -> Dictionary:
	if not _corpse:
		return {}
	return {
		"corpse_id": _corpse.corpse_id,
		"items": _corpse.get_loot_items(),
		"owner_info": _corpse.get_owner_info(),
		"remaining_time": _corpse.get_remaining_time()
	}

## Loot from corpse
func loot_from_corpse(looter: Entity, item_index: int = -1) -> Dictionary:
	if not _corpse:
		return {"success": false, "reason": "No corpse"}

	if not _corpse.can_loot(looter):
		return {"success": false, "reason": "Too far from corpse"}

	if item_index >= 0:
		return _corpse.loot_item(looter, item_index)
	else:
		# Loot all
		return {"success": true, "items": _corpse.loot_all(looter)}

## Self-rez using an item (soul gem)
var _self_rez_cooldown: float = 0.0

func use_self_rez_item(item: Item) -> Dictionary:
	if not _is_dead:
		return {"success": false, "reason": "Not dead"}

	if not item.is_self_rez_item:
		return {"success": false, "reason": "Item cannot self-resurrect"}

	# Check if being revived (prevent self-rez while healer is casting)
	if RespawnService and RespawnService.is_being_revived(get_parent().entity_id):
		return {"success": false, "reason": "Cannot self-rez while being revived"}

	# Check cooldown
	if _self_rez_cooldown > 0:
		return {"success": false, "reason": "Self-rez on cooldown (%.0fs remaining)" % _self_rez_cooldown}

	# Check config
	if not GameConfig.Respawn.ENABLE_SELF_REZ:
		return {"success": false, "reason": "Self-rez disabled"}

	var entity: Node3D = get_parent()

	# Remove the item from inventory
	if entity.inventory_component:
		var removed: bool = entity.inventory_component.remove_item_by_id(item.id, 1)
		if not removed:
			return {"success": false, "reason": "No self-rez item in inventory"}

	# Perform the res
	var health_percent := item.self_rez_health_percent if item.self_rez_health_percent > 0 else GameConfig.Respawn.SELF_REZ_HEALTH_PERCENT
	var mana_percent := item.self_rez_mana_percent if item.self_rez_mana_percent > 0 else GameConfig.Respawn.SELF_REZ_MANA_PERCENT

	current_health = int(max_health * health_percent)
	current_health = maxi(1, current_health)  # At least 1 HP
	_is_dead = false
	_respawn_timer = 0.0

	# Restore mana if entity has mana
	if entity.has_method("restore_mana"):
		var mana_to_restore := int(entity.max_mana * mana_percent)
		entity.restore_mana(mana_to_restore)

	# Remove corpse
	_remove_corpse()

	# Cancel any active revive on this player
	if RespawnService:
		RespawnService.interrupt_revival(entity.entity_id, "Self-rez used")

	# Set cooldown
	_self_rez_cooldown = item.self_rez_cooldown if item.self_rez_cooldown > 0 else GameConfig.Respawn.SELF_REZ_COOLDOWN

	# Emit signals
	respawned.emit()
	EventHub.entity_spawned.emit(entity, null)
	EventHub.self_resurrected.emit(entity, item)

	GameLog.info("HealthComponent: %s self-resurrected using %s" % [entity.display_name, item.display_name])

	return {
		"success": true,
		"health_restored": current_health,
		"mana_restored": entity.max_mana * mana_percent if entity.has_method("restore_mana") else 0
	}

## Get self-rez cooldown remaining
func get_self_rez_cooldown() -> float:
	return _self_rez_cooldown

## Check if can use self-rez item
func can_use_self_rez_item() -> bool:
	if not _is_dead:
		return false
	if _self_rez_cooldown > 0:
		return false
	if not GameConfig.Respawn.ENABLE_SELF_REZ:
		return false
	return true
