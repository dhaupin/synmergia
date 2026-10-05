## EventHub - Unified event system interface
##
## Wraps all domain-specific event buses under one autoload
extends Node

const SpawnMetadata = preload("res://core/events/spawn_metadata.gd")
## Forwarding signals for backward compatibility (maps to entity_events)
signal entity_spawned(entity, metadata: SpawnMetadata)
signal entity_died(entity, killer, metadata: SpawnMetadata)
signal player_died(entity, killer)
signal player_resurrected(entity, source: String)
signal self_resurrected(entity)
signal player_respawned(entity, position: Vector3, mode)
## Payload is the entity NODE + SpawnMetadata (EntityService.unregister
## is the only emitter; the old (entity_id, reason) annotation never
## matched it and the typed consumers prove the node shape).
signal entity_despawned(entity, metadata: SpawnMetadata)
# Emitted by HealthComponent with (killer, victim, damage_type) object
# args -- matches the death_features streak handler and combat_events.gd.
signal entity_killed(killer, victim, damage_type: String)
signal entity_targeted(target_id: String, source_id: String)
signal skill_executed(caster_id: String, skill_id: String, target_ids: Array)
signal revive_completed(entity, success: bool)
## Direct combat signals (emitted by health_component.take_damage,
## Entity.take_damage, and Enemy.take_damage; consumed by AggroComponent
## for threat tracking and the HUD combat surfaces).
## is_crit rides along so DamageNumbers/log/toasts can style crits
## without re-rolling; emitters that don't roll crits pass false.
signal damage_dealt(source, target, amount: int, damage_type: String, is_crit: bool)

## A hit-table roll resolved (combat_math.gd, run by Skill.calculate_damage
## and EnemyAI._perform_attack). outcome is the full hit table Dictionary
## (hit_result enum, is_crit, blocked_damage, ...), skill may be null for
## plain enemy swings. Emitted for BOTH landed hits and miss-family
## outcomes (amount 0) so the HUD can show "Miss"/"Dodged" floats and
## defender toasts. Consumed by the world HUD bridge.
signal hit_resolved(attacker, defender, outcome: Dictionary, skill, amount: int)

## Heals applied to any combatant (health_component.heal, the skill.gd
## heal path). Mirrors damage_dealt so healing is as visible as damage
## on the HUD surfaces (heal floats + combat-log lines).
signal heal_dealt(source, target, amount: int)

## XP/gold kill reward paid out (kill_rewards.gd). Consumers: HUD
## floating reward text, kill stat tracking, quest kill objectives.
signal kill_rewarded(entity, killer, rewards: Dictionary)

## Zone transitions (ZoneManager.entity_enter_zone / entity_exit_zone and
## the gateway path). Payload is the entity node and the ZoneData resource.
signal entity_entered_zone(entity, zone)
signal entity_exited_zone(entity, zone)

## Teleport via gateway (world_service.gd).
signal entity_teleported(entity, from_pos: Vector3, to_pos: Vector3)

## PvP kill attribution (health_component.gd on player death).
signal player_killed_player(killer, victim)

## Combat channel state (combat_component.gd).
signal entity_entered_combat(entity)
signal entity_exited_combat(entity)
signal channel_tick(entity, skill)
signal entity_interrupted(entity, skill, reason)
signal interrupt_resisted(entity, skill)

## Aura/buff lifecycle (aura_component.gd).
signal buff_applied(entity, buff, source)
signal buff_removed(entity, buff)
signal debuff_applied(entity, debuff, source)
signal debuff_removed(entity, debuff)
signal aura_activated(entity, aura)
signal aura_deactivated(entity, aura)
signal aura_dispelled(entity, aura, caster)
signal effect_dispelled(entity, debuff, caster)

## Target-frame effect list (target_frame.gd). Payload is a plain
## snapshot Dictionary (id/name/description/is_debuff/remaining/stack/
## icon_path) so the UI never holds a live StatusEffect reference.
signal entity_effect_added(entity_id: String, effect_data: Dictionary)
signal entity_effect_removed(entity_id: String, effect_id: String)

## Gold balance changes (inventory_component.gd add_gold / remove_gold).
signal gold_changed(entity, amount: int)

## Projectile lifecycle (projectile.gd).
signal projectile_hit(projectile, target, damage: int)
signal projectile_expired(projectile)
signal area_damage(source, target, damage: int, damage_type: String)
signal explosion_occurred(position: Vector3, radius: float, source)

## Targeting UI actions (target_tooltip.gd).
signal target_action_executed(source_id: String, target_id: String, action_id: String, success: bool)

## Accessibility settings broadcasts (SettingsPanel -> interested UI panels).
signal accessibility_text_scale_changed(scale: float)
signal accessibility_reduce_motion_changed(enabled: bool)
signal accessibility_high_contrast_changed(enabled: bool)

## Corpse lifecycle (HealthComponent creates/removes corpse nodes).
signal corpse_created(entity, corpse, killer)
signal corpse_removed(entity_id: String)

## Inventory events (InventoryComponent emits both; the signals were
## missing from the hub, a latent runtime error on every pickup/overflow).
signal item_picked_up(entity, item)
signal inventory_full(entity)
signal item_dropped(entity, item)

## Ground loot lifecycle (GroundLootService): items on the ground from
## enemy drops, PvP deaths, chests, and reward bundles.
signal ground_loot_spawned(loot_id: String, position: Vector3, items: Array)
signal ground_loot_picked_up(player, loot_id: String, items: Array)
signal ground_loot_despawned(loot_id: String, reason: String)

## Spawn metadata for entity lifecycle events
## SpawnMetadata now lives in core/events/spawn_metadata.gd
## Domain-specific event buses (use these to emit/listen)
var entity
var combat
var inventory
var system

func _ready() -> void:
	# Load and instantiate domain event buses
	# Using load() to ensure classes are available
	var entity_class = load("res://core/events/entity_events.gd")
	var combat_class = load("res://core/events/combat_events.gd")
	var inventory_class = load("res://core/events/inventory_events.gd")
	var system_class = load("res://core/events/system_events.gd")

	entity = entity_class.new()
	combat = combat_class.new()
	inventory = inventory_class.new()
	system = system_class.new()

	add_child(entity)
	add_child(combat)
	add_child(inventory)
	add_child(system)

	# Forward entity_events to direct signals for backward compatibility
	entity.spawned.connect(_on_entity_spawned)
	entity.died.connect(_on_entity_died)

	GameLog.info("EventHub: Initialized")

func _on_entity_spawned(entity_id: String, zone_id: String, position: Vector3) -> void:
	entity_spawned.emit(entity_id, null)

func _on_entity_died(entity_id: String, killer_id: String, damage_type: String) -> void:
	player_died.emit(entity_id, killer_id)
	entity_died.emit(entity_id, killer_id, null)

## Get event summary for debugging
func get_summary() -> Dictionary:
	return {
		"entity_events": entity.get_event_count(),
		"combat_events": combat.get_event_count(),
		"inventory_events": inventory.get_event_count(),
		"system_events": system.get_event_count(),
	}

## Clear all event history
func clear_all_history() -> void:
	entity.clear_history()
	combat.clear_history()
	inventory.clear_history()
	system.clear_history()
